<#
.SYNOPSIS
    Quick diagnostic script to troubleshoot Velociraptor server web GUI access issues

.DESCRIPTION
    Checks service status, ports, firewall, and logs to diagnose why web GUI is not accessible
    
.PARAMETER ServerName
    Optional server name or IP address to test remote connections (defaults to localhost)
    
.EXAMPLE
    .\Test-VelociraptorServer.ps1
    
.EXAMPLE
    .\Test-VelociraptorServer.ps1 -ServerName "192.168.1.100"
#>

param(
    [string]$ServerName = "localhost"
)

Write-Host "=== Velociraptor Server Diagnostic ===" -ForegroundColor Cyan
Write-Host "Testing server: $ServerName" -ForegroundColor Gray
Write-Host ""
Write-Host ""

# 1. Check service status
Write-Host "1. Checking service status..." -ForegroundColor Yellow
$service = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "   Service Name: $($service.Name)" -ForegroundColor Green
    Write-Host "   Display Name: $($service.DisplayName)" -ForegroundColor Green
    Write-Host "   Status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq 'Running') { 'Green' } else { 'Red' })
    Write-Host "   Start Type: $($service.StartType)" -ForegroundColor Green
}
else {
    Write-Host "   ERROR: Service 'Velociraptor' not found!" -ForegroundColor Red
    Write-Host "   Trying to find any Velociraptor service..." -ForegroundColor Yellow
    $allServices = Get-Service | Where-Object { $_.Name -like "*velociraptor*" -or $_.DisplayName -like "*velociraptor*" }
    if ($allServices) {
        Write-Host "   Found services:" -ForegroundColor Yellow
        $allServices | ForEach-Object { Write-Host "     - $($_.Name) ($($_.Status))" -ForegroundColor Yellow }
    }
}
Write-Host ""

# 2. Check if ports are listening
Write-Host "2. Checking if ports are listening..." -ForegroundColor Yellow
$ports = @(8000, 8889)
foreach ($port in $ports) {
    $listening = netstat -ano | findstr ":$port" | findstr "LISTENING"
    if ($listening) {
        Write-Host "   Port ${port}: LISTENING" -ForegroundColor Green
        $listening | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    }
    else {
        Write-Host "   Port ${port}: NOT LISTENING" -ForegroundColor Red
    }
}
Write-Host ""

# 3. Test connection to ports
Write-Host "3. Testing connection to ports on $ServerName..." -ForegroundColor Yellow
foreach ($port in $ports) {
    try {
        $test = Test-NetConnection -ComputerName $ServerName -Port $port -WarningAction SilentlyContinue
        if ($test.TcpTestSucceeded) {
            Write-Host "   Port ${port}: Connection successful" -ForegroundColor Green
        }
        else {
            Write-Host "   Port ${port}: Connection failed" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "   Port ${port}: Connection failed - $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ""

# 4. Check firewall rules
Write-Host "4. Checking firewall rules..." -ForegroundColor Yellow
$firewallRules = Get-NetFirewallRule -DisplayName "Velociraptor*" -ErrorAction SilentlyContinue
if ($firewallRules) {
    Write-Host "   Found firewall rules:" -ForegroundColor Green
    $firewallRules | ForEach-Object {
        $rule = $_
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        $action = $rule.Action
        $port = if ($portFilter) { $portFilter.LocalPort } else { "unknown" }
        Write-Host "     - $($rule.DisplayName): $action on port $port" -ForegroundColor $(if ($rule.Enabled) { 'Green' } else { 'Yellow' })
        if (!$rule.Enabled) {
            Write-Host "       WARNING: Rule is disabled!" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "   WARNING: No Velociraptor firewall rules found!" -ForegroundColor Red
}
Write-Host ""

# 5. Check service binary path configuration
Write-Host "5. Checking service binary path configuration..." -ForegroundColor Yellow
$serviceQuery = sc.exe qc Velociraptor 2>&1
if ($LASTEXITCODE -eq 0) {
    $binaryPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
    if ($binaryPath) {
        Write-Host "   Service Binary Path: $binaryPath" -ForegroundColor Gray
        
        # Check if it's pointing to server executable
        $expectedServerPath = "C:\Program Files\Velociraptor Server\velociraptor.exe"
        if ($binaryPath -like "*Velociraptor Server*") {
            Write-Host "   [OK] Service is configured to use SERVER executable" -ForegroundColor Green
            
            # Extract config path from binary path if present
            if ($binaryPath -match '--config\s+"?([^"]+)"?') {
                $serviceConfigPath = $matches[1]
                Write-Host "   Service Config Path: $serviceConfigPath" -ForegroundColor Green
            }
        }
        elseif ($binaryPath -like "*Velociraptor\Velociraptor.exe*" -and $binaryPath -notlike "*Velociraptor Server*") {
            Write-Host "   [X] CRITICAL: Service is configured to use CLIENT executable!" -ForegroundColor Red
            Write-Host "   Expected: $expectedServerPath" -ForegroundColor Yellow
            Write-Host "   Actual: $binaryPath" -ForegroundColor Red
            Write-Host "   This service needs to be reconfigured to use the server executable." -ForegroundColor Red
        }
        else {
            Write-Host "   [?] Unknown executable path - verify manually" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "   WARNING: Could not parse service binary path" -ForegroundColor Yellow
        Write-Host "   Raw output: $serviceQuery" -ForegroundColor Gray
    }
}
else {
    Write-Host "   ERROR: Could not query service configuration" -ForegroundColor Red
    Write-Host "   Output: $serviceQuery" -ForegroundColor Gray
}
Write-Host ""

# 6. Check configuration file
Write-Host "6. Checking configuration file..." -ForegroundColor Yellow
$configPath = "C:\Program Files\Velociraptor Server\server.config.yaml"
if (Test-Path $configPath) {
    Write-Host "   Config file exists: $configPath" -ForegroundColor Green
    
    # Try to read GUI port from config
    $configContent = Get-Content $configPath -Raw
    if ($configContent -match 'GUI:[\s\S]*?bind_port:\s*(\d+)') {
        $guiPort = $matches[1]
        Write-Host "   GUI Port in config: $guiPort" -ForegroundColor Green
    }
    if ($configContent -match 'Frontend:[\s\S]*?bind_port:\s*(\d+)') {
        $frontendPort = $matches[1]
        Write-Host "   Frontend Port in config: $frontendPort" -ForegroundColor Green
    }
    
    # Check GUI bind_address (critical for remote access)
    if ($configContent -match 'GUI:[\s\S]*?bind_address:\s*([^\s\r\n]+)') {
        $guiBindAddress = $matches[1].Trim()
        Write-Host "   GUI Bind Address: $guiBindAddress" -ForegroundColor $(if ($guiBindAddress -eq '0.0.0.0') { 'Green' } else { 'Yellow' })
        if ($guiBindAddress -eq '127.0.0.1' -or $guiBindAddress -eq 'localhost') {
            Write-Host "   [X] WARNING: GUI is bound to localhost only!" -ForegroundColor Red
            Write-Host "   Remote access will not work. Change to 0.0.0.0 for remote access." -ForegroundColor Yellow
        }
        elseif ($guiBindAddress -eq '0.0.0.0') {
            Write-Host "   [OK] GUI is bound to all interfaces (remote access enabled)" -ForegroundColor Green
        }
    }
    
    # Check Frontend bind_address
    if ($configContent -match 'Frontend:[\s\S]*?bind_address:\s*([^\s\r\n]+)') {
        $frontendBindAddress = $matches[1].Trim()
        Write-Host "   Frontend Bind Address: $frontendBindAddress" -ForegroundColor $(if ($frontendBindAddress -eq '0.0.0.0') { 'Green' } else { 'Yellow' })
    }
    
    # Check for SSL settings
    if ($configContent -match 'use_plain_http:\s*(true|false)') {
        $usePlainHttp = $matches[1]
        Write-Host "   Use Plain HTTP: $usePlainHttp" -ForegroundColor $(if ($usePlainHttp -eq 'true') { 'Yellow' } else { 'Green' })
        if ($usePlainHttp -eq 'false') {
            Write-Host "   NOTE: Using HTTPS - make sure you use https:// in the URL" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "   ERROR: Config file not found at $configPath" -ForegroundColor Red
}
Write-Host ""

# 7. Check service logs
Write-Host "7. Checking service logs..." -ForegroundColor Yellow
$logPath = "C:\Program Files\Velociraptor Server\Logs"
$logPathAlt = "C:\Program Files\Velociraptor Server"
$logPaths = @($logPath, $logPathAlt)

$foundLogs = $false
foreach ($path in $logPaths) {
    if (Test-Path $path) {
        $logFiles = Get-ChildItem -Path $path -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5
        if ($logFiles) {
            Write-Host "   Recent log files in ${path}:" -ForegroundColor Green
            $foundLogs = $true
            foreach ($logFile in $logFiles) {
                Write-Host "     - $($logFile.Name) (Last modified: $($logFile.LastWriteTime))" -ForegroundColor Gray
                $errors = Get-Content $logFile.FullName -Tail 10 -ErrorAction SilentlyContinue | Select-String -Pattern "error|Error|ERROR|failed|Failed|FAILED" -CaseSensitive:$false
                if ($errors) {
                    Write-Host "       Recent errors found:" -ForegroundColor Red
                    $errors | ForEach-Object { Write-Host "         $_" -ForegroundColor Red }
                }
            }
        }
    }
}

if (!$foundLogs) {
    Write-Host "   No log files found in expected locations" -ForegroundColor Yellow
    Write-Host "   Checking service executable path..." -ForegroundColor Yellow
    $service = Get-WmiObject Win32_Service -Filter "Name='Velociraptor'" -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "   Service executable: $($service.PathName)" -ForegroundColor Gray
        $serviceDir = Split-Path $service.PathName -Parent
        Write-Host "   Service directory: $serviceDir" -ForegroundColor Gray
        if (Test-Path $serviceDir) {
            $serviceLogs = Get-ChildItem -Path $serviceDir -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3
            if ($serviceLogs) {
                Write-Host "   Found logs in service directory:" -ForegroundColor Green
                $serviceLogs | ForEach-Object { Write-Host "     - $($_.FullName)" -ForegroundColor Gray }
            }
        }
    }
}
Write-Host ""

# 8. Check Windows Event Log
Write-Host "8. Checking Windows Event Log..." -ForegroundColor Yellow
$events = Get-EventLog -LogName Application -Source "*Velociraptor*" -Newest 5 -ErrorAction SilentlyContinue
if ($events) {
    Write-Host "   Recent Velociraptor events:" -ForegroundColor Green
    $events | ForEach-Object {
        $color = if ($_.EntryType -eq 'Error') { 'Red' } elseif ($_.EntryType -eq 'Warning') { 'Yellow' } else { 'Green' }
        Write-Host "     [$($_.TimeGenerated)] $($_.EntryType): $($_.Message)" -ForegroundColor $color
    }
}
else {
    Write-Host "   No Velociraptor events found in Application log" -ForegroundColor Yellow
}
Write-Host ""

# 9. Check if process is actually running
Write-Host "9. Checking if Velociraptor process is running..." -ForegroundColor Yellow
$process = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
if ($process) {
    Write-Host "   Process found: PID $($process.Id)" -ForegroundColor Green
    Write-Host "   Process path: $($process.Path)" -ForegroundColor Gray
    Write-Host "   CPU time: $($process.CPU)" -ForegroundColor Gray
    Write-Host "   Memory: $([math]::Round($process.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Gray
    
    # Check if process path matches expected server installation
    $expectedServerPath = "C:\Program Files\Velociraptor Server\velociraptor.exe"
    $processDir = Split-Path $process.Path -Parent
    
    if ($process.Path -notlike "*Velociraptor Server*") {
        Write-Host "" -ForegroundColor Red
        Write-Host "   *** CRITICAL ISSUE DETECTED ***" -ForegroundColor Red
        Write-Host "   Process is running from: $processDir" -ForegroundColor Red
        Write-Host "   Expected server path: C:\Program Files\Velociraptor Server\" -ForegroundColor Yellow
        Write-Host "   This appears to be the CLIENT installation, not the SERVER!" -ForegroundColor Red
        Write-Host "   The service is running the wrong executable." -ForegroundColor Red
        Write-Host "" -ForegroundColor Yellow
        Write-Host "   SOLUTION:" -ForegroundColor Yellow
        Write-Host "   1. Stop the current service: Stop-Service -Name 'Velociraptor'" -ForegroundColor White
        Write-Host "   2. Remove the client service: sc.exe delete Velociraptor" -ForegroundColor White
        Write-Host "   3. Reinstall server service from: C:\Program Files\Velociraptor Server\" -ForegroundColor White
        Write-Host "      cd 'C:\Program Files\Velociraptor Server'" -ForegroundColor Gray
        Write-Host "      .\velociraptor.exe --config server.config.yaml service install" -ForegroundColor Gray
    }
}
else {
    Write-Host "   WARNING: No velociraptor.exe process found!" -ForegroundColor Red
    Write-Host "   Service shows as running but process is not active" -ForegroundColor Red
    Write-Host "   This usually means the service crashed or failed to start" -ForegroundColor Yellow
}
Write-Host ""

# 10. Summary and recommendations
Write-Host "=== Summary and Recommendations ===" -ForegroundColor Cyan
Write-Host ""

# Check service status (refresh to get current state)
$service.Refresh()
if ($service -and $service.Status -eq 'Running') {
    Write-Host "[OK] Service is running" -ForegroundColor Green
    
    # Verify service binary path
    $serviceQuery = sc.exe qc Velociraptor 2>&1
    if ($LASTEXITCODE -eq 0) {
        $binaryPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
        if ($binaryPath -like "*Velociraptor Server*") {
            Write-Host "[OK] Service binary path points to SERVER executable" -ForegroundColor Green
        }
        elseif ($binaryPath -like "*Velociraptor\Velociraptor.exe*" -and $binaryPath -notlike "*Velociraptor Server*") {
            Write-Host "[X] Service binary path points to CLIENT executable (WRONG!)" -ForegroundColor Red
            Write-Host "  -> Service needs to be reconfigured. Run on server:" -ForegroundColor Yellow
            Write-Host "     Stop-Service -Name 'Velociraptor'" -ForegroundColor Gray
            Write-Host "     sc.exe delete Velociraptor" -ForegroundColor Gray
            Write-Host "     cd 'C:\Program Files\Velociraptor Server'" -ForegroundColor Gray
            Write-Host "     .\velociraptor.exe --config server.config.yaml service install" -ForegroundColor Gray
            Write-Host ""
        }
    }
    
    if ($process) {
        $processDir = Split-Path $process.Path -Parent
        if ($process.Path -like "*Velociraptor Server*") {
            Write-Host "[OK] Velociraptor SERVER process is active" -ForegroundColor Green
        }
        else {
            Write-Host "[X] Velociraptor CLIENT process is running (wrong installation!)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[X] Velociraptor process NOT found - service may have crashed" -ForegroundColor Red
        Write-Host "  -> Check Windows Event Log: Get-EventLog -LogName Application -Source '*Velociraptor*' -Newest 10" -ForegroundColor Yellow
        Write-Host "  -> Try restarting: Restart-Service -Name 'Velociraptor'" -ForegroundColor Yellow
        Write-Host ""
    }
}
else {
    Write-Host "[X] Service is NOT running" -ForegroundColor Red
    Write-Host "  -> Try: Start-Service -Name 'Velociraptor'" -ForegroundColor Yellow
    Write-Host ""
}

# Verify GUI bind address
$configPath = "C:\Program Files\Velociraptor Server\server.config.yaml"
if (Test-Path $configPath) {
    $configContent = Get-Content $configPath -Raw
    if ($configContent -match 'GUI:[\s\S]*?bind_address:\s*([^\s\r\n]+)') {
        $guiBindAddress = $matches[1].Trim()
        if ($guiBindAddress -eq '0.0.0.0') {
            Write-Host "[OK] GUI bind address is 0.0.0.0 (remote access enabled)" -ForegroundColor Green
        }
        elseif ($guiBindAddress -eq '127.0.0.1' -or $guiBindAddress -eq 'localhost') {
            Write-Host "[X] GUI bind address is $guiBindAddress (localhost only - remote access disabled)" -ForegroundColor Red
            Write-Host "  -> Edit config file and change GUI.bind_address to 0.0.0.0" -ForegroundColor Yellow
            Write-Host "  -> Then restart service: Restart-Service -Name 'Velociraptor'" -ForegroundColor Yellow
            Write-Host ""
        }
    }
}

$guiPort = 8889
$listening = netstat -ano | findstr ":$guiPort" | findstr "LISTENING"
if ($listening) {
    Write-Host "[OK] Port $guiPort is listening" -ForegroundColor Green
}
else {
    Write-Host "[X] Port $guiPort is NOT listening" -ForegroundColor Red
    if ($process) {
        Write-Host "  -> Process is running but not binding to port - check configuration" -ForegroundColor Yellow
        Write-Host "  -> Verify config: Get-Content 'C:\Program Files\Velociraptor Server\server.config.yaml' | Select-String -Pattern 'bind_port|GUI'" -ForegroundColor Yellow
    }
    else {
        Write-Host "  -> Process is not running - service likely crashed on startup" -ForegroundColor Yellow
        Write-Host "  -> Check service executable path and configuration" -ForegroundColor Yellow
    }
    Write-Host "  -> Check if port is in use: netstat -ano | findstr ':8889'" -ForegroundColor Yellow
    Write-Host "  -> Try restarting: Restart-Service -Name 'Velociraptor'" -ForegroundColor Yellow
    Write-Host ""
}

$firewallRules = Get-NetFirewallRule -DisplayName "Velociraptor GUI" -ErrorAction SilentlyContinue
if ($firewallRules -and ($firewallRules | Where-Object { $_.Enabled -eq $true })) {
    Write-Host "[OK] Firewall rule exists and is enabled" -ForegroundColor Green
}
else {
    Write-Host "[X] Firewall rule missing or disabled" -ForegroundColor Red
    Write-Host "  -> Create rule: New-NetFirewallRule -DisplayName 'Velociraptor GUI' -Direction Inbound -Protocol TCP -LocalPort 8889 -Action Allow" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Try accessing the web GUI at:" -ForegroundColor Cyan
Write-Host "  https://localhost:8889" -ForegroundColor White
Write-Host "  or" -ForegroundColor Gray
Write-Host "  https://<server-hostname-or-ip>:8889" -ForegroundColor White
Write-Host ""
Write-Host "To find your server hostname/IP:" -ForegroundColor Yellow
Write-Host "  hostname" -ForegroundColor Gray
Write-Host "  ipconfig" -ForegroundColor Gray
Write-Host ""
Write-Host "If using HTTPS with self-signed certificate, you may need to:" -ForegroundColor Yellow
Write-Host "  1. Accept the security warning in your browser" -ForegroundColor Yellow
Write-Host "  2. Click 'Advanced' then 'Proceed to localhost (unsafe)'" -ForegroundColor Yellow
Write-Host ""

