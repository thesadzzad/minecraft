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

echo [INFO] Pushing Minecraft server to R2 (r2:minecraft)...
echo.

rclone sync "%~dp0." "r2:minecraft" ^
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
