@echo off
setlocal
rem ==========================================================================
rem  Ultimate add-on updater for WoW Forever.
rem  1. Set ADDONS below to your WoW Forever AddOns folder (if yours differs).
rem  2. Close WoW (or /reload after), then double-click this file.
rem  Your settings and recorded kills live in WoW's WTF folder: they're kept.
rem ==========================================================================
if not defined ADDONS set "ADDONS=C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"

if not defined ZIP_URL set "ZIP_URL=https://github.com/Tal-Stein/WoWUltimateAddon/archive/refs/heads/main.zip"

if not exist "%ADDONS%\" (
  echo AddOns folder not found:
  echo   %ADDONS%
  echo Open this file in Notepad and set ADDONS to your WoW Forever AddOns folder.
  pause
  exit /b 1
)

rem Program Files needs administrator rights: ask for them if we can't write there.
(echo.>"%ADDONS%\.ultimate_write_test") 2>nul || (
  echo Asking for administrator rights to write to the AddOns folder...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
del "%ADDONS%\.ultimate_write_test" 2>nul

echo Downloading the latest Ultimate...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
  "$dst = Join-Path $env:ADDONS 'Ultimate';" ^
  "if ((Test-Path $dst) -and ((Get-Item $dst -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'AddOns\Ultimate is a link (a developer setup); not touching it.' }" ^
  "$t = Join-Path $env:TEMP 'ultimate-update';" ^
  "if (Test-Path $t) { Remove-Item $t -Recurse -Force };" ^
  "New-Item -ItemType Directory $t | Out-Null;" ^
  "Invoke-WebRequest $env:ZIP_URL -OutFile (Join-Path $t 'u.zip') -UseBasicParsing;" ^
  "Expand-Archive (Join-Path $t 'u.zip') $t -Force;" ^
  "$src = Join-Path $t 'WoWUltimateAddon-main\Ultimate';" ^
  "if (-not (Test-Path (Join-Path $src 'Ultimate.toc'))) { throw 'The download did not contain the add-on.' };" ^
  "if (Test-Path $dst) { Remove-Item $dst -Recurse -Force };" ^
  "Copy-Item $src $env:ADDONS -Recurse;" ^
  "Remove-Item $t -Recurse -Force;" ^
  "$v = (Select-String -Path (Join-Path $dst 'Ultimate.toc') -Pattern '^## Version:\s*(.+)$').Matches.Groups[1].Value;" ^
  "Write-Host ('Ultimate updated' + $(if ($v) { ' to ' + $v } else { '' }) + '.')"
if errorlevel 1 (
  echo.
  echo The update failed; see the message above. Nothing else was changed.
) else (
  echo Done. Start WoW, or type /reload if it's running.
)
pause
