@echo off
rem Double-click to download Mist-UI's artwork (see install-artwork.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-artwork.ps1" %*
if errorlevel 1 (
    echo.
    echo The artwork could not be installed. See the message above, or the manual steps in README.md.
)
echo.
pause
