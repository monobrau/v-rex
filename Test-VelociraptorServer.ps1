<#
.SYNOPSIS
    Quick diagnostic script to troubleshoot Velociraptor server web GUI access issues

.DESCRIPTION
    Checks service status, ports, firewall, and logs to diagnose why web GUI is not accessible
#>

Write-Host "=== Velociraptor Server Diagnostic ===" -ForegroundColor Cyan
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
        Write-Host "   Port $port: LISTENING" -ForegroundColor Green
        $listening | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    }
    else {
        Write-Host "   Port $port: NOT LISTENING" -ForegroundColor Red
    }
}
Write-Host ""

# 3. Test local connection
Write-Host "3. Testing local connection to ports..." -ForegroundColor Yellow
foreach ($port in $ports) {
    try {
        $test = Test-NetConnection -ComputerName localhost -Port $port -WarningAction SilentlyContinue
        if ($test.TcpTestSucceeded) {
            Write-Host "   Port $port: Connection successful" -ForegroundColor Green
        }
        else {
            Write-Host "   Port $port: Connection failed" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "   Port $port: Connection failed - $($_.Exception.Message)" -ForegroundColor Red
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
        $action = Get-NetFirewallAction -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        Write-Host "     - $($rule.DisplayName): $($action.Action) on port $($portFilter.LocalPort)" -ForegroundColor $(if ($rule.Enabled) { 'Green' } else { 'Yellow' })
        if (!$rule.Enabled) {
            Write-Host "       WARNING: Rule is disabled!" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "   WARNING: No Velociraptor firewall rules found!" -ForegroundColor Red
}
Write-Host ""

# 5. Check configuration file
Write-Host "5. Checking configuration file..." -ForegroundColor Yellow
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

# 6. Check service logs
Write-Host "6. Checking service logs..." -ForegroundColor Yellow
$logPath = "C:\Program Files\Velociraptor Server\Logs"
if (Test-Path $logPath) {
    $logFiles = Get-ChildItem -Path $logPath -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    if ($logFiles) {
        Write-Host "   Recent log files:" -ForegroundColor Green
        foreach ($logFile in $logFiles) {
            Write-Host "     - $($logFile.Name) (Last modified: $($logFile.LastWriteTime))" -ForegroundColor Gray
            $errors = Get-Content $logFile.FullName -Tail 10 | Select-String -Pattern "error|Error|ERROR|failed|Failed|FAILED" -CaseSensitive:$false
            if ($errors) {
                Write-Host "       Recent errors found:" -ForegroundColor Red
                $errors | ForEach-Object { Write-Host "         $_" -ForegroundColor Red }
            }
        }
    }
    else {
        Write-Host "   No log files found in $logPath" -ForegroundColor Yellow
    }
}
else {
    Write-Host "   Log directory not found: $logPath" -ForegroundColor Yellow
}
Write-Host ""

# 7. Check Windows Event Log
Write-Host "7. Checking Windows Event Log..." -ForegroundColor Yellow
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

# 8. Summary and recommendations
Write-Host "=== Summary and Recommendations ===" -ForegroundColor Cyan
Write-Host ""

if ($service -and $service.Status -eq 'Running') {
    Write-Host "✓ Service is running" -ForegroundColor Green
}
else {
    Write-Host "✗ Service is NOT running" -ForegroundColor Red
    Write-Host "  → Try: Start-Service -Name 'Velociraptor'" -ForegroundColor Yellow
    Write-Host ""
}

$guiPort = 8889
$listening = netstat -ano | findstr ":$guiPort" | findstr "LISTENING"
if ($listening) {
    Write-Host "✓ Port $guiPort is listening" -ForegroundColor Green
}
else {
    Write-Host "✗ Port $guiPort is NOT listening" -ForegroundColor Red
    Write-Host "  → Check service logs for errors" -ForegroundColor Yellow
    Write-Host "  → Verify configuration file is correct" -ForegroundColor Yellow
    Write-Host ""
}

$firewallRules = Get-NetFirewallRule -DisplayName "Velociraptor GUI" -ErrorAction SilentlyContinue
if ($firewallRules -and ($firewallRules | Where-Object { $_.Enabled -eq $true })) {
    Write-Host "✓ Firewall rule exists and is enabled" -ForegroundColor Green
}
else {
    Write-Host "✗ Firewall rule missing or disabled" -ForegroundColor Red
    Write-Host "  → Create rule: New-NetFirewallRule -DisplayName 'Velociraptor GUI' -Direction Inbound -Protocol TCP -LocalPort 8889 -Action Allow" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Try accessing the web GUI at:" -ForegroundColor Cyan
Write-Host "  https://localhost:8889" -ForegroundColor White
Write-Host "  or" -ForegroundColor Gray
Write-Host "  https://DC-05.dorks.lan:8889" -ForegroundColor White
Write-Host ""
Write-Host "If using HTTPS with self-signed certificate, you may need to:" -ForegroundColor Yellow
Write-Host "  1. Accept the security warning in your browser" -ForegroundColor Yellow
Write-Host "  2. Click 'Advanced' → 'Proceed to localhost (unsafe)'" -ForegroundColor Yellow
Write-Host ""

