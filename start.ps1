$ErrorActionPreference = "Continue"
$ServerDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location -Path $ServerDir

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Minecraft Server Launcher with Discord Notices" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$WebhookUrl = "https://ptb.discord.com/api/webhooks/1555769183927672842/hx3833CrDWaxqfdjrBY4hoP81vx1dnNpdfPaGkOHueu4529d-pGMKQ6c4cUpmIyV0jYc"

# Function to locate Java 21+
function Find-JavaRuntime {
    $candidates = @(
        (Join-Path $env:APPDATA "squidservers\java\jdk-25\bin\java.exe"),
        (Join-Path $env:APPDATA "PrismLauncher\java\java-runtime-epsilon\bin\java.exe"),
        (Join-Path $env:APPDATA "PrismLauncher\java\java-runtime-delta\bin\java.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Eclipse Adoptium\*\bin\java.exe"),
        "C:\Program Files\Eclipse Adoptium\jdk-21*\bin\java.exe",
        "C:\Program Files\Java\jdk-21*\bin\java.exe",
        "C:\Program Files\Java\jdk-25*\bin\java.exe",
        "C:\Program Files\Microsoft\jdk-21*\bin\java.exe"
    )
    if ($env:JAVA_HOME) {
        $candidates += (Join-Path $env:JAVA_HOME "bin\java.exe")
    }

    foreach ($cand in $candidates) {
        if (-not $cand) { continue }
        $resolved = Resolve-Path $cand -ErrorAction SilentlyContinue
        if ($resolved) {
            foreach ($r in $resolved) {
                $exe = $r.Path
                if (Test-Path $exe) {
                    $verOutput = & $exe -version 2>&1 | Out-String
                    if ($verOutput -match 'version "(?<ver>[0-9]+)') {
                        $major = [int]$Matches['ver']
                        if ($major -ge 21) {
                            return $exe
                        }
                    }
                }
            }
        }
    }

    if (Get-Command java -ErrorAction SilentlyContinue) {
        $verOutput = & java -version 2>&1 | Out-String
        if ($verOutput -match 'version "(?<ver>[0-9]+)') {
            $major = [int]$Matches['ver']
            if ($major -ge 21) {
                return (Get-Command java).Source
            }
        }
    }

    return $null
}

$JavaExe = Find-JavaRuntime

if (-not $JavaExe) {
    Write-Host "[WARNING] No Java 21 or newer was detected on your system!" -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $installPrompt = Read-Host "Would you like to auto-install Java 21 (Temurin) via winget? (Y/n)"
        if ([string]::IsNullOrWhiteSpace($installPrompt) -or $installPrompt.Trim().ToLower() -eq 'y') {
            Write-Host "Installing Eclipse Adoptium Temurin 21..." -ForegroundColor Cyan
            winget install EclipseAdoptium.Temurin.21.JRE --accept-source-agreements --accept-package-agreements --silent
            $JavaExe = Find-JavaRuntime
        }
    }
}

if (-not $JavaExe) {
    Write-Host ""
    Write-Host "[ERROR] Could not find or install Java 21+." -ForegroundColor Red
    Write-Host "Modern Minecraft servers require Java 21 or newer." -ForegroundColor Red
    Write-Host "Please download Java 21 manually from: https://adoptium.net/temurin/releases/?version=21" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit..."
    exit 1
}

Write-Host "[INFO] Using Java: $JavaExe" -ForegroundColor Green
Write-Host ""

# Fetch Server Port from server.properties if present
$ServerPort = "25565"
$ServerPropsPath = Join-Path $ServerDir "server.properties"
if (Test-Path $ServerPropsPath) {
    $propsContent = Get-Content $ServerPropsPath -ErrorAction SilentlyContinue
    foreach ($line in $propsContent) {
        if ($line -match '^\s*server-port\s*=\s*(?<port>\d+)') {
            $ServerPort = $Matches['port']
            break
        }
    }
}

# Fetch Public IP with short timeout
Write-Host "[INFO] Detecting public IP address..." -ForegroundColor Cyan
$PublicIp = try {
    (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 3).Trim()
} catch {
    try {
        (Invoke-RestMethod -Uri "https://icanhazip.com" -TimeoutSec 3).Trim()
    } catch {
        "Unavailable (Ask host)"
    }
}

$HostName = [System.Environment]::UserName
$StartTime = Get-Date

# Send Discord Webhook Helper
function Send-DiscordWebhook {
    param (
        [string]$Title,
        [string]$Description,
        [int]$Color,
        [array]$Fields
    )
    $payload = @{
        username = "Minecraft Server"
        avatar_url = "https://raw.githubusercontent.com/FabricMC/fabric-loader/master/src/main/resources/assets/fabric/icon.png"
        embeds = @(
            @{
                title = $Title
                description = $Description
                color = $Color
                fields = $Fields
                footer = @{ text = "Cloudflare R2 Minecraft Sync" }
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        )
    } | ConvertTo-Json -Depth 5

    try {
        $null = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 5
        return $true
    } catch {
        Write-Host "[WARNING] Discord notification failed: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Ensure playit.gg tunnel is running if installed
$PlayitExe = "C:\Program Files\playit_gg\bin\playit.exe"
if (Test-Path $PlayitExe) {
    Write-Host "[INFO] Starting playit.gg tunnel service..." -ForegroundColor Cyan
    $null = & $PlayitExe start 2>&1
}

Write-Host "[INFO] Sending Discord notification: Server Online..." -ForegroundColor Cyan
$onlineFields = @(
    @{ name = "Host"; value = "$HostName"; inline = $true },
    @{ name = "Version"; value = "26.3 (Fabric)"; inline = $true },
    @{ name = "Host Connect (Same PC)"; value = "localhost or 127.0.0.1"; inline = $false },
    @{ name = "Friends Connect (Internet)"; value = "$PublicIp`:$ServerPort (or playit.gg tunnel)"; inline = $false }
)
$sent = Send-DiscordWebhook -Title "[ONLINE] Minecraft Server is Online!" -Description "The server has started and is ready for players to connect." -Color 3066993 -Fields $onlineFields
if ($sent) {
    Write-Host "[SUCCESS] Discord notification posted." -ForegroundColor Green
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host " [CONNECTION GUIDE]" -ForegroundColor Yellow
Write-Host "   - IF YOU ARE THE HOST (This PC):" -ForegroundColor Cyan
Write-Host "     Connect using: localhost" -ForegroundColor White
Write-Host "   - IF YOUR FRIEND IS CONNECTING (Internet):" -ForegroundColor Cyan
Write-Host "     Connect using: Your playit.gg domain OR $PublicIp`:$ServerPort" -ForegroundColor White
Write-Host "===================================================" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "[INFO] Starting Minecraft server..." -ForegroundColor Cyan
Write-Host "[TIP] To cleanly stop the server, type 'stop' into the console and press Enter." -ForegroundColor Yellow
Write-Host ""

# Launch Server (stdin/stdout remain attached for console interaction)
$ServerJar = Join-Path $ServerDir "server.jar"
if (-not (Test-Path $ServerJar)) {
    Write-Host "[ERROR] server.jar not found in $ServerDir!" -ForegroundColor Red
    Write-Host "Please run pull.bat first to download the server files." -ForegroundColor Yellow
    Read-Host "Press Enter to exit..."
    exit 1
}

& $JavaExe -Xms2G -Xmx4G -jar $ServerJar nogui
$ServerExitCode = $LASTEXITCODE

$StopTime = Get-Date
$Duration = $StopTime - $StartTime
$DurationString = "{0}h {1}m {2}s" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Minecraft Server Stopped (Session: $DurationString)" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# Send Discord Webhook: Server Offline
Write-Host "[INFO] Sending Discord notification: Server Offline..." -ForegroundColor Cyan
$offlineFields = @(
    @{ name = "Host"; value = "$HostName"; inline = $true },
    @{ name = "Session Duration"; value = "$DurationString"; inline = $true },
    @{ name = "Next Step"; value = "Syncing world save to Cloudflare R2"; inline = $true }
)
$null = Send-DiscordWebhook -Title "[OFFLINE] Minecraft Server is Offline" -Description "The server was stopped. World save is ready to sync." -Color 15158332 -Fields $offlineFields

Write-Host ""
# Prompt to push to R2 immediately
$PushBat = Join-Path $ServerDir "push.bat"
if (Test-Path $PushBat) {
    $doPush = Read-Host "Would you like to sync your progress to R2 now with push.bat? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($doPush) -or $doPush.Trim().ToLower() -eq 'y') {
        Write-Host ""
        & $PushBat
    } else {
        Write-Host ""
        Write-Host "Remember to run push.bat before your friend hosts!" -ForegroundColor Yellow
        Read-Host "Press Enter to exit..."
    }
} else {
    Read-Host "Press Enter to exit..."
}
