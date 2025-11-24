<#
.SYNOPSIS
    Fixes Velociraptor service to use the correct server executable

.DESCRIPTION
    Stops and removes the incorrectly configured Velociraptor service,
    then reinstalls it pointing to the server executable and configuration.

.PARAMETER ServerPath
    Path to the Velociraptor Server installation directory
    Default: "C:\Program Files\Velociraptor Server"

.PARAMETER ConfigFile
    Name of the server configuration file
    Default: "server.config.yaml"

.EXAMPLE
    .\Fix-VelociraptorService.ps1
    
.EXAMPLE
    .\Fix-VelociraptorService.ps1 -ServerPath "D:\Velociraptor Server" -ConfigFile "server.config.yaml"
#>

param(
    [string]$ServerPath = "C:\Program Files\Velociraptor Server",
    [string]$ConfigFile = "server.config.yaml"
)

# Require admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Fixing Velociraptor Service Configuration ===" -ForegroundColor Cyan
Write-Host ""

# Verify server path exists
$serverExe = Join-Path $ServerPath "velociraptor.exe"
$configPath = Join-Path $ServerPath $ConfigFile

if (-not (Test-Path $serverExe)) {
    Write-Host "ERROR: Server executable not found at: $serverExe" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: Configuration file not found at: $configPath" -ForegroundColor Red
    exit 1
}

Write-Host "Server executable: $serverExe" -ForegroundColor Green
Write-Host "Configuration file: $configPath" -ForegroundColor Green
Write-Host ""

# Step 1: Check current service status
Write-Host "Step 1: Checking current service status..." -ForegroundColor Yellow
$service = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "   Service found: $($service.Name) - Status: $($service.Status)" -ForegroundColor Gray
    
    # Check current binary path
    $serviceQuery = sc.exe qc Velociraptor 2>&1
    if ($LASTEXITCODE -eq 0) {
        $binaryPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
        Write-Host "   Current binary path: $binaryPath" -ForegroundColor Gray
        
        if ($binaryPath -like "*Velociraptor Server*") {
            Write-Host "   [OK] Service is already configured correctly!" -ForegroundColor Green
            Write-Host "   No changes needed." -ForegroundColor Green
            exit 0
        }
    }
    
    # Step 2: Stop the service
    Write-Host ""
    Write-Host "Step 2: Stopping Velociraptor service..." -ForegroundColor Yellow
    if ($service.Status -eq 'Running') {
        try {
            Stop-Service -Name "Velociraptor" -Force -ErrorAction Stop
            Write-Host "   Service stopped successfully" -ForegroundColor Green
            
            # Wait a moment for the service to fully stop
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Host "   ERROR: Failed to stop service: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   Attempting to continue anyway..." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "   Service is already stopped" -ForegroundColor Gray
    }
    
    # Step 3: Delete the service
    Write-Host ""
    Write-Host "Step 3: Removing incorrectly configured service..." -ForegroundColor Yellow
    try {
        $deleteResult = sc.exe delete Velociraptor 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   Service removed successfully" -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
        else {
            Write-Host "   WARNING: Service deletion returned exit code $LASTEXITCODE" -ForegroundColor Yellow
            Write-Host "   Output: $deleteResult" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "   ERROR: Failed to delete service: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "   No existing Velociraptor service found" -ForegroundColor Gray
}

# Step 4: Verify config file bind address
Write-Host ""
Write-Host "Step 4: Verifying configuration file..." -ForegroundColor Yellow

# Read config file as lines to preserve structure
$configLines = Get-Content $configPath
$configContent = Get-Content $configPath -Raw
$needsConfigFix = $false
$inGuiSection = $false
$guiBindAddress = $null

# Find GUI bind address by parsing line by line
for ($i = 0; $i -lt $configLines.Count; $i++) {
    $line = $configLines[$i]
    
    # Detect GUI section start
    if ($line -match '^GUI:\s*$' -or $line -match '^GUI:') {
        $inGuiSection = $true
    }
    # Detect next top-level section (starts at column 0)
    elseif ($inGuiSection -and $line -match '^[A-Z][^:]*:\s*$' -and $line -notmatch '^\s') {
        $inGuiSection = $false
    }
    
    # Find bind_address in GUI section
    if ($inGuiSection -and $line -match '^\s+bind_address:\s*(.+)$') {
        $guiBindAddress = $matches[1].Trim()
        Write-Host "   GUI bind address: $guiBindAddress" -ForegroundColor Gray
        
        if ($guiBindAddress -eq '127.0.0.1' -or $guiBindAddress -eq 'localhost') {
            Write-Host "   WARNING: GUI is bound to localhost only!" -ForegroundColor Yellow
            Write-Host "   Would you like to change it to 0.0.0.0 for remote access? (Y/N)" -ForegroundColor Yellow
            $response = Read-Host
            if ($response -eq 'Y' -or $response -eq 'y') {
                Write-Host "   Updating GUI bind address to 0.0.0.0..." -ForegroundColor Yellow
                # Update just this line, preserving indentation
                $indent = $line -match '^(\s+)bind_address:' | Out-Null
                $indent = if ($matches) { $matches[1] } else { "  " }
                $configLines[$i] = "${indent}bind_address: 0.0.0.0"
                $needsConfigFix = $true
            }
        }
        elseif ($guiBindAddress -eq '0.0.0.0') {
            Write-Host "   [OK] GUI bind address is correct (0.0.0.0)" -ForegroundColor Green
        }
        break
    }
}

# Write updated config if needed
if ($needsConfigFix) {
    try {
        # Backup original config
        $backupPath = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $configPath $backupPath -Force
        Write-Host "   Backup created: $backupPath" -ForegroundColor Gray
        
        # Write updated config
        $configLines | Set-Content $configPath -Encoding UTF8
        Write-Host "   Configuration updated" -ForegroundColor Green
        
        # Validate YAML syntax by trying to read it
        $testContent = Get-Content $configPath -Raw
        if (-not $testContent) {
            throw "Config file appears empty after update"
        }
    }
    catch {
        Write-Host "   ERROR: Failed to update config file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Restoring from backup..." -ForegroundColor Yellow
        if (Test-Path $backupPath) {
            Copy-Item $backupPath $configPath -Force
        }
        exit 1
    }
}

# Step 5: Fix windows_installer path in config (if present)
Write-Host ""
Write-Host "Step 5: Updating windows_installer path in config..." -ForegroundColor Yellow
$configLines = Get-Content $configPath
$configUpdated = $false
$inWindowsInstaller = $false

for ($i = 0; $i -lt $configLines.Count; $i++) {
    $line = $configLines[$i]
    
    if ($line -match '^windows_installer:') {
        $inWindowsInstaller = $true
    }
    elseif ($inWindowsInstaller -and $line -match '^[A-Z]') {
        $inWindowsInstaller = $false
    }
    
    if ($inWindowsInstaller -and $line -match '^\s+install_path:\s*(.+)$') {
        $currentPath = $matches[1].Trim()
        if ($currentPath -notlike "*Velociraptor Server*") {
            Write-Host "   Updating install_path from client to server path..." -ForegroundColor Yellow
            $indent = if ($line -match '^(\s+)install_path:') { $matches[1] } else { "    " }
            $serverInstallPath = '$ProgramFiles\Velociraptor Server\velociraptor.exe'
            $configLines[$i] = "${indent}install_path: $serverInstallPath"
            $configUpdated = $true
        }
        else {
            Write-Host "   install_path is already correct" -ForegroundColor Gray
        }
    }
}

if ($configUpdated) {
    try {
        $backupPath = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $configPath $backupPath -Force
        Write-Host "   Backup created: $backupPath" -ForegroundColor Gray
        $configLines | Set-Content $configPath -Encoding UTF8
        Write-Host "   Config updated successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "   WARNING: Could not update config: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Step 6: Install service with correct path using sc.exe directly
Write-Host ""
Write-Host "Step 6: Installing service with correct server executable..." -ForegroundColor Yellow

# Use sc.exe directly to ensure correct path, bypassing config's windows_installer settings
$serviceName = "Velociraptor"
$binPath = "`"$serverExe`" --config `"$configPath`" service run"

try {
    Write-Host "   Creating service with sc.exe..." -ForegroundColor Gray
    $createResult = sc.exe create $serviceName binPath= $binPath start= auto DisplayName= "Velociraptor" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Service created successfully" -ForegroundColor Green
        
        # Set service description
        sc.exe description $serviceName "Velociraptor Server" | Out-Null
        
        # Configure failure actions
        sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
    }
    else {
        Write-Host "   ERROR: Service creation failed" -ForegroundColor Red
        Write-Host "   Output: $createResult" -ForegroundColor Gray
        
        # Try Velociraptor's service install as fallback
        Write-Host "   Trying Velociraptor's service install as fallback..." -ForegroundColor Yellow
        Push-Location $ServerPath
        try {
            $installArgs = @("--config", $ConfigFile, "service", "install")
            $output = & $serverExe $installArgs 2>&1
            $exitCode = $LASTEXITCODE
            
            if ($exitCode -ne 0) {
                Write-Host "   ERROR: Fallback installation also failed" -ForegroundColor Red
                Write-Host "   Output: $output" -ForegroundColor Gray
                Pop-Location
                exit 1
            }
        }
        finally {
            Pop-Location
        }
    }
}
catch {
    Write-Host "   ERROR: Failed to install service: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 7: Verify service configuration
Write-Host ""
Write-Host "Step 7: Verifying service configuration..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
$serviceQuery = sc.exe qc Velociraptor 2>&1
if ($LASTEXITCODE -eq 0) {
    $binaryPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
    Write-Host "   Service binary path: $binaryPath" -ForegroundColor Gray
    
    if ($binaryPath -like "*Velociraptor Server*") {
        Write-Host "   [OK] Service is now configured correctly!" -ForegroundColor Green
    }
    else {
        Write-Host "   WARNING: Service path still doesn't look correct" -ForegroundColor Yellow
        Write-Host "   Actual path: $binaryPath" -ForegroundColor Gray
        Write-Host "   Expected: *Velociraptor Server*" -ForegroundColor Gray
        Write-Host "   Please verify manually: sc.exe qc Velociraptor" -ForegroundColor Yellow
    }
}
else {
    Write-Host "   WARNING: Could not verify service configuration" -ForegroundColor Yellow
}

# Step 8: Start the service
Write-Host ""
Write-Host "Step 8: Starting Velociraptor service..." -ForegroundColor Yellow
try {
    Start-Service -Name "Velociraptor" -ErrorAction Stop
    Write-Host "   Service started successfully" -ForegroundColor Green
    
    # Wait a moment for the service to start
    Start-Sleep -Seconds 3
    
    # Get service object to verify status
    $service = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
    if ($service) {
        $service.Refresh()
        if ($service.Status -eq 'Running') {
            Write-Host "   [OK] Service is running" -ForegroundColor Green
        }
        else {
            Write-Host "   WARNING: Service status is $($service.Status)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "   WARNING: Could not retrieve service status" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "   ERROR: Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   You may need to start it manually: Start-Service -Name 'Velociraptor'" -ForegroundColor Yellow
}

# Step 9: Final verification
Write-Host ""
Write-Host "Step 9: Final verification..." -ForegroundColor Yellow
$process = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
if ($process) {
    Write-Host "   Process found: PID $($process.Id)" -ForegroundColor Green
    Write-Host "   Process path: $($process.Path)" -ForegroundColor Gray
    
    if ($process.Path -like "*Velociraptor Server*") {
        Write-Host "   [OK] Correct SERVER executable is running!" -ForegroundColor Green
    }
    else {
        Write-Host "   [X] Process is still running from wrong path!" -ForegroundColor Red
        Write-Host "   Please restart the service: Restart-Service -Name 'Velociraptor'" -ForegroundColor Yellow
    }
}
else {
    Write-Host "   WARNING: No velociraptor process found" -ForegroundColor Yellow
    Write-Host "   Service may still be starting, or there may be an issue" -ForegroundColor Yellow
}

# Check ports
Write-Host ""
Write-Host "Checking if ports are listening..." -ForegroundColor Yellow
$ports = @(8000, 8889)
foreach ($port in $ports) {
    $listening = netstat -ano | findstr ":$port" | findstr "LISTENING"
    if ($listening) {
        Write-Host "   Port ${port}: LISTENING" -ForegroundColor Green
    }
    else {
        Write-Host "   Port ${port}: NOT LISTENING (may take a few seconds to start)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Service Fix Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Wait a few seconds for the service to fully start" -ForegroundColor White
Write-Host "  2. Run diagnostic script: .\Test-VelociraptorServer.ps1" -ForegroundColor White
Write-Host "  3. Try accessing the web GUI: https://<server-ip>:8889" -ForegroundColor White
Write-Host ""

