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

echo [INFO] Pulling latest server files from R2 (r2:minecraft)...
echo.

rclone sync "r2:minecraft" "%~dp0." ^
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
