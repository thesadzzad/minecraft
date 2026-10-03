$ErrorActionPreference = "Stop"
$ServerDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Cloudflare R2 Minecraft Sync Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "This setup will configure Cloudflare R2 and generate" -ForegroundColor Gray
Write-Host "exactly 2 files: pull.bat and push.bat" -ForegroundColor Gray
Write-Host ""

# 1. Install or locate Rclone
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
    if (Test-Path (Join-Path $wingetLinks "rclone.exe")) {
        $env:Path = "$wingetLinks;$env:Path"
    }
}

if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "==> Installing Rclone via winget..." -ForegroundColor Yellow
        winget install Rclone.Rclone --accept-source-agreements --accept-package-agreements --silent
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
        $env:Path = "$wingetLinks;$machinePath;$userPath"
    }

    if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
        Write-Error "Rclone is not found in PATH. Please install Rclone manually from https://rclone.org/downloads/ or restart your terminal."
        exit 1
    }
}
Write-Host "==> Rclone is installed and ready." -ForegroundColor Green
Write-Host ""

# 2. Collect Cloudflare credentials
$AccountId = (Read-Host "Enter Cloudflare Account ID").Trim()
if ([string]::IsNullOrWhiteSpace($AccountId)) {
    Write-Error "Cloudflare Account ID cannot be empty."
    exit 1
}

$AccessKey = (Read-Host "Enter R2 Access Key ID").Trim()
if ([string]::IsNullOrWhiteSpace($AccessKey)) {
    Write-Error "R2 Access Key ID cannot be empty."
    exit 1
}

$SecretKeySecure = Read-Host -AsSecureString "Enter R2 Secret Access Key"
$PlainSecretKey = [System.Net.NetworkCredential]::new("", $SecretKeySecure).Password.Trim()
if ([string]::IsNullOrWhiteSpace($PlainSecretKey)) {
    Write-Error "R2 Secret Access Key cannot be empty."
    exit 1
}

$Bucket = (Read-Host "Enter R2 Bucket Name [default: minecraft-backup]").Trim()
if ([string]::IsNullOrWhiteSpace($Bucket)) { $Bucket = "minecraft-backup" }

$Endpoint = "https://$AccountId.r2.cloudflarestorage.com"
$RemoteName = "r2"

# 3. Configure Rclone remote
Write-Host "==> Configuring Rclone remote '$RemoteName'..." -ForegroundColor Yellow
& rclone config create $RemoteName s3 provider Cloudflare access_key_id $AccessKey secret_access_key $PlainSecretKey endpoint $Endpoint --non-interactive
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure Rclone remote '$RemoteName'."
    exit $LASTEXITCODE
}

# 4. Verify bucket connection (supports bucket-scoped API tokens)
Write-Host "==> Verifying connection to R2 bucket '$Bucket'..." -ForegroundColor Yellow
$verifyOutput = & rclone lsf "${RemoteName}:${Bucket}" --max-depth 1 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Bucket '$Bucket' not found or empty. Attempting to ensure bucket exists..." -ForegroundColor Yellow
    $null = & rclone mkdir "${RemoteName}:${Bucket}" 2>&1
    $verifyOutput = & rclone lsf "${RemoteName}:${Bucket}" --max-depth 1 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Verification output:`n$verifyOutput" -ForegroundColor Red
        Write-Error "Failed to access Cloudflare R2 bucket '$Bucket'. Check your credentials, Account ID, and bucket permissions."
        exit 1
    }
}
Write-Host "==> Connection to bucket '$Bucket' successful!" -ForegroundColor Green
Write-Host ""

# Clean up any legacy files from older setup versions so only 2 files remain
$legacyFiles = @("push.ps1", "pull.ps1", "rclone-ignore.txt", "Pull", "Push", "Pushing")
foreach ($f in $legacyFiles) {
    $path = Join-Path $ServerDir $f
    if (Test-Path $path) {
        Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
    }
}

# 5. Generate pull.bat
Write-Host "==> Generating pull.bat..." -ForegroundColor Yellow
$PullBatContent = @"
@echo off
setlocal
title Minecraft Server Sync - PULL from Cloudflare R2

if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\rclone.exe" (
    set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
)

echo ===================================================
echo  Cloudflare R2 Minecraft Sync: PULL
echo ===================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-Process java -ErrorAction SilentlyContinue) { Write-Host '[WARNING] Java is currently running! If your Minecraft server is active, stop it before pulling to prevent file lock errors or corruption.' -ForegroundColor Yellow; Write-Host '' }"

echo [INFO] Pulling latest server files from R2 (${RemoteName}:${Bucket})...
echo.

rclone sync "${RemoteName}:${Bucket}" "%~dp0." ^
    --exclude "session.lock" ^
    --exclude "*.log" ^
    --exclude "logs/**" ^
    --exclude "crash-reports/**" ^
    --exclude ".fabric/**" ^
    --exclude "cache/**" ^
    --exclude ".mc_server_state.json" ^
    --exclude ".git/**" ^
    --exclude ".gitignore" ^
    --exclude "setup.ps1" ^
    --exclude "push.bat" ^
    --exclude "pull.bat" ^
    --transfers 4 ^
    --checkers 8 ^
    --fast-list ^
    --verbose

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ===================================================
    echo [ERROR] Pull failed with exit code %ERRORLEVEL%.
    echo Check your internet connection or Cloudflare credentials.
    echo ===================================================
    echo.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ===================================================
echo [SUCCESS] Pull completed successfully!
echo You can now start and host your Minecraft server.
echo ===================================================
echo.
pause
"@
Set-Content -Path (Join-Path $ServerDir "pull.bat") -Value $PullBatContent -Encoding ASCII

# 6. Generate push.bat
Write-Host "==> Generating push.bat..." -ForegroundColor Yellow
$PushBatContent = @"
@echo off
setlocal
title Minecraft Server Sync - PUSH to Cloudflare R2

if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\rclone.exe" (
    set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
)

echo ===================================================
echo  Cloudflare R2 Minecraft Sync: PUSH
echo ===================================================
echo.

if not exist "%~dp0server.jar" (
    if not exist "%~dp0world" (
        echo [ERROR] Safety check failed!
        echo No server.jar or world folder found in this directory.
        echo If you are setting up or switching hosts, you MUST run pull.bat first!
        echo Push cancelled to prevent accidentally wiping the Cloudflare R2 bucket.
        echo.
        pause
        exit /b 1
    )
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-Process java -ErrorAction SilentlyContinue) { Write-Host '[WARNING] Java is currently running! Make sure your Minecraft server is completely STOPPED before pushing, otherwise world data may be incomplete or corrupted.' -ForegroundColor Yellow; Write-Host '' }"

echo [INFO] Pushing Minecraft server to R2 (${RemoteName}:${Bucket})...
echo.

rclone sync "%~dp0." "${RemoteName}:${Bucket}" ^
    --exclude "session.lock" ^
    --exclude "*.log" ^
    --exclude "logs/**" ^
    --exclude "crash-reports/**" ^
    --exclude ".fabric/**" ^
    --exclude "cache/**" ^
    --exclude ".mc_server_state.json" ^
    --exclude ".git/**" ^
    --exclude ".gitignore" ^
    --exclude "setup.ps1" ^
    --exclude "push.bat" ^
    --exclude "pull.bat" ^
    --transfers 4 ^
    --checkers 8 ^
    --fast-list ^
    --verbose

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ===================================================
    echo [ERROR] Push failed with exit code %ERRORLEVEL%.
    echo Check your internet connection or Cloudflare credentials.
    echo ===================================================
    echo.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ===================================================
echo [SUCCESS] Push completed successfully!
echo The server is synced to R2. Your friend can now pull and host.
echo ===================================================
echo.
pause
"@
Set-Content -Path (Join-Path $ServerDir "push.bat") -Value $PushBatContent -Encoding ASCII

Write-Host "==========================================" -ForegroundColor Green
Write-Host " Setup complete! Exactly 2 files created:" -ForegroundColor Green
Write-Host "   1. pull.bat  -> Pull server before hosting" -ForegroundColor Cyan
Write-Host "   2. push.bat  -> Push server after closing" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

# Ask to pull immediately if server files are not present
if (-not (Test-Path (Join-Path $ServerDir "server.jar"))) {
    $initialPull = Read-Host "Would you like to pull the server files now? (Y/n)"
    if ([string]::IsNullOrWhiteSpace($initialPull) -or $initialPull.Trim().ToLower() -eq 'y') {
        Write-Host "==> Starting initial pull..." -ForegroundColor Cyan
        & (Join-Path $ServerDir "pull.bat")
    }
}
