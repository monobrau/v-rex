<#
.SYNOPSIS
    Check if the correct Velociraptor server executable is installed
#>

$serverExe = "C:\Program Files\Velociraptor Server\velociraptor.exe"

Write-Host "=== Checking Velociraptor Executable ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $serverExe)) {
    Write-Host "ERROR: Executable not found at: $serverExe" -ForegroundColor Red
    exit 1
}

Write-Host "Executable found: $serverExe" -ForegroundColor Green
Write-Host ""

# Get file info
$fileInfo = Get-Item $serverExe
Write-Host "File Information:" -ForegroundColor Yellow
Write-Host "  Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray
Write-Host "  Last Modified: $($fileInfo.LastWriteTime)" -ForegroundColor Gray
Write-Host ""

# Get version info
Write-Host "Version Information:" -ForegroundColor Yellow
$versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($serverExe)
if ($versionInfo.FileVersion) {
    Write-Host "  File Version: $($versionInfo.FileVersion)" -ForegroundColor Gray
}
if ($versionInfo.ProductVersion) {
    Write-Host "  Product Version: $($versionInfo.ProductVersion)" -ForegroundColor Gray
}
if ($versionInfo.ProductName) {
    Write-Host "  Product Name: $($versionInfo.ProductName)" -ForegroundColor Gray
}
Write-Host ""

# Try to get version from executable
Write-Host "Checking executable capabilities..." -ForegroundColor Yellow
Push-Location (Split-Path $serverExe -Parent)
try {
    # Try version command
    $versionOutput = & $serverExe version 2>&1
    if ($LASTEXITCODE -eq 0 -or $versionOutput) {
        Write-Host "Version command output:" -ForegroundColor Green
        $versionOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    
    Write-Host ""
    Write-Host "Checking available commands..." -ForegroundColor Yellow
    $helpOutput = & $serverExe --help 2>&1 | Select-Object -First 20
    Write-Host "Available commands (first 20 lines):" -ForegroundColor Gray
    $helpOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    
    # Check if it has server-specific commands
    $allHelp = & $serverExe --help 2>&1
    if ($allHelp -match 'config generate|frontend|service') {
        Write-Host ""
        Write-Host "[OK] Executable has server commands (config generate, frontend, service)" -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "[X] WARNING: Executable may not have server commands" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Could not run version check: $($_.Exception.Message)" -ForegroundColor Yellow
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== Recommendations ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Velociraptor uses the SAME executable for both server and client." -ForegroundColor Yellow
Write-Host "The difference is in the configuration file:" -ForegroundColor Yellow
Write-Host "  - Server config: Has 'Frontend:' and 'GUI:' sections" -ForegroundColor White
Write-Host "  - Client config: Has 'Client:' section with server_urls" -ForegroundColor White
Write-Host ""
Write-Host "If you downloaded from GitHub releases:" -ForegroundColor Yellow
Write-Host "  - Use: velociraptor-vX.X.X-windows-amd64.exe" -ForegroundColor White
Write-Host "  - This is the correct executable for server" -ForegroundColor White
Write-Host ""
Write-Host "If you're having issues, verify:" -ForegroundColor Yellow
Write-Host "  1. You downloaded from: https://github.com/Velocidex/velociraptor/releases" -ForegroundColor White
Write-Host "  2. You got the Windows amd64 version" -ForegroundColor White
Write-Host "  3. The file is not corrupted" -ForegroundColor White
Write-Host ""

