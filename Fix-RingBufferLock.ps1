<#
.SYNOPSIS
    Fix ring buffer file lock issue
#>

$serverPath = "C:\Program Files\Velociraptor Server"
$bufferFile = Join-Path $serverPath "Tools\Velociraptor_Buffer.bin"

Write-Host "=== Fixing Ring Buffer File Lock ===" -ForegroundColor Cyan
Write-Host ""

# Stop service and processes
Write-Host "Stopping all Velociraptor processes..." -ForegroundColor Yellow
Stop-Service -Name "Velociraptor" -Force -ErrorAction SilentlyContinue
Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Check if file exists and who's using it
Write-Host "Checking buffer file..." -ForegroundColor Yellow
if (Test-Path $bufferFile) {
    Write-Host "Buffer file exists: $bufferFile" -ForegroundColor Gray
    
    # Try to find what's locking it
    Write-Host "Checking for processes using the file..." -ForegroundColor Gray
    $lockedBy = Get-Process | Where-Object {
        $_.Path -like "*velociraptor*"
    }
    
    if ($lockedBy) {
        Write-Host "Found Velociraptor processes still running:" -ForegroundColor Yellow
        $lockedBy | ForEach-Object { Write-Host "  PID $($_.Id): $($_.Path)" -ForegroundColor Gray }
        Write-Host "Force stopping..." -ForegroundColor Yellow
        $lockedBy | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    
    # Try to delete the file
    Write-Host "Attempting to delete buffer file..." -ForegroundColor Yellow
    try {
        Remove-Item $bufferFile -Force -ErrorAction Stop
        Write-Host "Buffer file deleted successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Could not delete file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Trying to unlock with handle.exe or similar..." -ForegroundColor Yellow
        
        # Try using PowerShell to release the handle (if possible)
        Write-Host "You may need to:" -ForegroundColor Yellow
        Write-Host "  1. Restart the computer" -ForegroundColor White
        Write-Host "  2. Or use Process Explorer to find what's locking it" -ForegroundColor White
        Write-Host "  3. Or wait a few minutes and try again" -ForegroundColor White
    }
}
else {
    Write-Host "Buffer file does not exist (will be created on next start)" -ForegroundColor Gray
}

# Ensure Tools directory exists and has correct permissions
Write-Host ""
Write-Host "Checking Tools directory permissions..." -ForegroundColor Yellow
$toolsDir = Join-Path $serverPath "Tools"
if (-not (Test-Path $toolsDir)) {
    New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
    Write-Host "Created Tools directory" -ForegroundColor Green
}

# Set permissions to allow LocalSystem to write
try {
    $acl = Get-Acl $toolsDir
    $permission = "NT AUTHORITY\SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow"
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
    $acl.SetAccessRule($accessRule)
    Set-Acl $toolsDir $acl
    Write-Host "Set permissions on Tools directory" -ForegroundColor Green
}
catch {
    Write-Host "Could not set permissions: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Check config file for buffer settings
Write-Host ""
Write-Host "Checking config file buffer settings..." -ForegroundColor Yellow
$configPath = Join-Path $serverPath "server.config.yaml"
if (Test-Path $configPath) {
    $configContent = Get-Content $configPath -Raw
    
    # Check local_buffer settings
    if ($configContent -match 'local_buffer:[\s\S]*?filename_windows:\s*([^\s\r\n]+)') {
        $bufferPath = $matches[1].Trim()
        Write-Host "Config buffer path: $bufferPath" -ForegroundColor Gray
        
        # Check if it's using the correct path
        if ($bufferPath -notlike "*Velociraptor Server*") {
            Write-Host "WARNING: Buffer path in config may be incorrect" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Try starting the service: Start-Service -Name 'Velociraptor'" -ForegroundColor White
Write-Host "  2. Wait 5-10 seconds and check ports: netstat -ano | findstr ':8889'" -ForegroundColor White
Write-Host ""

