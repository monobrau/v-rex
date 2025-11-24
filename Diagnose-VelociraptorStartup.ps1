<#
.SYNOPSIS
    Diagnose why Velociraptor isn't binding to ports
#>

$serverPath = "C:\Program Files\Velociraptor Server"
$configPath = Join-Path $serverPath "server.config.yaml"
$serverExe = Join-Path $serverPath "velociraptor.exe"

Write-Host "=== Velociraptor Startup Diagnosis ===" -ForegroundColor Cyan
Write-Host ""

# Check if process is running
Write-Host "1. Checking for running processes..." -ForegroundColor Yellow
$processes = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
if ($processes) {
    Write-Host "   Found $($processes.Count) process(es):" -ForegroundColor Green
    foreach ($proc in $processes) {
        $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId=$($proc.Id)").CommandLine
        Write-Host "     PID $($proc.Id): $cmdLine" -ForegroundColor Gray
    }
}
else {
    Write-Host "   No velociraptor process found" -ForegroundColor Yellow
}

# Check service
Write-Host ""
Write-Host "2. Checking service..." -ForegroundColor Yellow
$service = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "   Service Status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' })
    $serviceQuery = & sc.exe qc Velociraptor 2>&1
    if ($LASTEXITCODE -eq 0) {
        $binPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
        Write-Host "   Service binPath: $binPath" -ForegroundColor Gray
        if ($binPath -notmatch '--config') {
            Write-Host "   [X] WARNING: Service is missing --config parameter!" -ForegroundColor Red
        }
        else {
            Write-Host "   [OK] Service has --config parameter" -ForegroundColor Green
        }
    }
}
else {
    Write-Host "   Service not found" -ForegroundColor Yellow
}

# Check config file
Write-Host ""
Write-Host "3. Checking configuration file..." -ForegroundColor Yellow
if (Test-Path $configPath) {
    Write-Host "   Config file exists: $configPath" -ForegroundColor Green
    
    # Try to validate config
    Write-Host "   Validating config syntax..." -ForegroundColor Gray
    Push-Location $serverPath
    try {
        $validateOutput = & $serverExe --config server.config.yaml config show 2>&1
        $validateExit = $LASTEXITCODE
        
        if ($validateExit -eq 0) {
            Write-Host "   [OK] Config file is valid" -ForegroundColor Green
        }
        else {
            Write-Host "   [X] Config file has errors:" -ForegroundColor Red
            $validateOutput | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
        }
    }
    catch {
        Write-Host "   [X] Error validating config: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
    
    # Check key config values
    $configContent = Get-Content $configPath -Raw
    if ($configContent -match 'GUI:[\s\S]*?bind_address:\s*([^\s\r\n]+)') {
        $guiBind = $matches[1].Trim()
        Write-Host "   GUI bind_address: $guiBind" -ForegroundColor Gray
    }
    if ($configContent -match 'GUI:[\s\S]*?bind_port:\s*(\d+)') {
        $guiPort = $matches[1]
        Write-Host "   GUI bind_port: $guiPort" -ForegroundColor Gray
    }
    if ($configContent -match 'Frontend:[\s\S]*?bind_port:\s*(\d+)') {
        $frontendPort = $matches[1]
        Write-Host "   Frontend bind_port: $frontendPort" -ForegroundColor Gray
    }
    
    # Check datastore
    if ($configContent -match 'Datastore:[\s\S]*?location:\s*([^\s\r\n]+)') {
        $datastore = $matches[1].Trim()
        Write-Host "   Datastore location: $datastore" -ForegroundColor Gray
        if (Test-Path $datastore) {
            Write-Host "   [OK] Datastore path exists" -ForegroundColor Green
        }
        else {
            Write-Host "   [X] Datastore path does not exist!" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "   [X] Config file not found!" -ForegroundColor Red
}

# Check logs
Write-Host ""
Write-Host "4. Checking logs..." -ForegroundColor Yellow
$logPath = Join-Path $serverPath "Logs"
if (Test-Path $logPath) {
    $logFiles = Get-ChildItem -Path $logPath -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    if ($logFiles) {
        Write-Host "   Found log files:" -ForegroundColor Green
        foreach ($log in $logFiles) {
            Write-Host "     $($log.Name) (Last modified: $($log.LastWriteTime))" -ForegroundColor Gray
            $errors = Get-Content $log.FullName -Tail 20 -ErrorAction SilentlyContinue | Select-String -Pattern "error|Error|ERROR|failed|Failed|FAILED|panic|Panic" -CaseSensitive:$false
            if ($errors) {
                Write-Host "       Recent errors:" -ForegroundColor Red
                $errors | Select-Object -First 5 | ForEach-Object { Write-Host "         $_" -ForegroundColor Red }
            }
        }
    }
    else {
        Write-Host "   No log files found" -ForegroundColor Yellow
    }
}
else {
    Write-Host "   Log directory not found: $logPath" -ForegroundColor Yellow
}

# Check Windows Event Log
Write-Host ""
Write-Host "5. Checking Windows Event Log..." -ForegroundColor Yellow
$events = Get-EventLog -LogName Application -Source "*Velociraptor*" -Newest 10 -ErrorAction SilentlyContinue
if ($events) {
    Write-Host "   Recent events:" -ForegroundColor Green
    $events | ForEach-Object {
        $color = if ($_.EntryType -eq 'Error') { 'Red' } elseif ($_.EntryType -eq 'Warning') { 'Yellow' } else { 'Gray' }
        Write-Host "     [$($_.TimeGenerated)] $($_.EntryType): $($_.Message)" -ForegroundColor $color
    }
}
else {
    Write-Host "   No Velociraptor events found" -ForegroundColor Yellow
}

# Try running manually to see errors
Write-Host ""
Write-Host "6. Testing manual execution (5 seconds)..." -ForegroundColor Yellow
if ($processes) {
    Write-Host "   Stopping existing processes first..." -ForegroundColor Gray
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Push-Location $serverPath
try {
    $testProcess = Start-Process -FilePath $serverExe -ArgumentList "--config", "server.config.yaml", "service", "run" -NoNewWindow -PassThru -RedirectStandardOutput "test_stdout.txt" -RedirectStandardError "test_stderr.txt"
    
    Start-Sleep -Seconds 5
    
    if (-not $testProcess.HasExited) {
        Write-Host "   [OK] Process is running" -ForegroundColor Green
        Stop-Process -Id $testProcess.Id -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "   [X] Process exited with code: $($testProcess.ExitCode)" -ForegroundColor Red
    }
    
    if (Test-Path "test_stderr.txt") {
        $errors = Get-Content "test_stderr.txt" -ErrorAction SilentlyContinue
        if ($errors) {
            Write-Host "   Errors from stderr:" -ForegroundColor Red
            $errors | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
        }
        Remove-Item "test_stderr.txt" -ErrorAction SilentlyContinue
    }
    
    if (Test-Path "test_stdout.txt") {
        $output = Get-Content "test_stdout.txt" -ErrorAction SilentlyContinue
        if ($output) {
            Write-Host "   Output from stdout:" -ForegroundColor Gray
            $output | Select-Object -Last 10 | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
        }
        Remove-Item "test_stdout.txt" -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Host "   [X] Error running manually: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Pop-Location
}

# Check ports
Write-Host ""
Write-Host "7. Checking ports..." -ForegroundColor Yellow
$ports = @(8000, 8889)
foreach ($port in $ports) {
    $listening = netstat -ano | findstr ":$port" | findstr "LISTENING"
    if ($listening) {
        Write-Host "   Port $port: LISTENING" -ForegroundColor Green
        $listening | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    }
    else {
        Write-Host "   Port $port: NOT LISTENING" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Diagnosis Complete ===" -ForegroundColor Cyan
Write-Host ""

