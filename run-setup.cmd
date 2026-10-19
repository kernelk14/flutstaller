@echo off
rem ---------------------------------------------------------------------------
rem  Launcher for the Flutter development environment setup.
rem
rem  The script it runs was written by an AI coding agent (OpenCode) from a
rem  written specification. It is MIT licensed and the whole program is one
rem  readable file - see install.ps1.
rem
rem  This launcher does NOT change the machine execution policy and does NOT
rem  use -ExecutionPolicy Bypass. Before running the script it checks whether
rem  PowerShell would refuse to execute it and, if so, prints the exact fix.
rem ---------------------------------------------------------------------------
setlocal

set "SCRIPT=%~dp0install.ps1"
set "FLUTSTALLER_SCRIPT=%SCRIPT%"

where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: powershell.exe was not found on PATH.
    exit /b 1
)

echo.
echo   flutstaller - Flutter development environment setup for Windows
echo   The script it runs was written by an AI coding agent ^(OpenCode^).
echo   It is MIT licensed and the whole program is one readable file: install.ps1
echo.

rem --- pre-flight: would PowerShell refuse to run the script? ------------------
rem  exit 0 = fine, 3 = blocked by the mark-of-the-web, 4 = policy is
rem  Restricted, 5 = policy is AllSigned and the file is not signed.
powershell -NoProfile -NoLogo -Command "$ErrorActionPreference='SilentlyContinue'; $p=$env:FLUTSTALLER_SCRIPT; $eff=Get-ExecutionPolicy; if($eff -eq 'Restricted'){exit 4}; if(-not (Test-Path -LiteralPath $p)){exit 0}; $signed=$false; $s=Get-AuthenticodeSignature -LiteralPath $p; if($s -and $s.Status -eq 'Valid'){$signed=$true}; $zone=Get-Item -LiteralPath $p -Stream 'Zone.Identifier'; if($zone -and -not $signed){exit 3}; if($eff -eq 'AllSigned' -and -not $signed){exit 5}; exit 0"
set "PF=%ERRORLEVEL%"

if "%PF%"=="3" goto BLOCKED_MARK
if "%PF%"=="4" goto BLOCKED_RESTRICTED
if "%PF%"=="5" goto BLOCKED_ALLSIGNED

rem --- run ---------------------------------------------------------------------
powershell -NoProfile -NoLogo -File "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo Setup finished with exit code %RC%.
    echo The full log is in the "logs" folder next to this script.
    echo.
    echo If PowerShell reported a script execution policy error, allow this one
    echo local file without changing the system policy:
    echo     powershell -NoProfile -Command "Unblock-File -LiteralPath '%SCRIPT%'"
    echo.
)

endlocal & exit /b %RC%

rem --- policy diagnostics ------------------------------------------------------
:BLOCKED_MARK
echo.
echo BLOCKED: Windows has marked this script as "downloaded from the internet"
echo and the execution policy is RemoteSigned, so PowerShell refuses to run an
echo unsigned file that carries that mark.
echo.
echo Fix - remove the mark from this single file. This changes no policy:
echo     powershell -NoProfile -Command "Unblock-File -LiteralPath '%SCRIPT%'"
echo.
echo Then run run-setup.cmd again.
endlocal & exit /b 3

:BLOCKED_RESTRICTED
echo.
echo BLOCKED: the execution policy is "Restricted", which blocks all script files.
echo.
echo Fix - allow local scripts for your user account. No administrator rights
echo are needed and RemoteSigned is the setting Microsoft recommends:
echo     Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
echo.
echo Then run run-setup.cmd again.
endlocal & exit /b 4

:BLOCKED_ALLSIGNED
echo.
echo BLOCKED: the execution policy is "AllSigned", so every script must carry a
echo valid code signature. This script is not signed.
echo.
echo Fix - switch your user account to RemoteSigned (local scripts run freely,
echo only downloaded scripts need a signature):
echo     Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
echo.
echo Then run run-setup.cmd again.
endlocal & exit /b 5
