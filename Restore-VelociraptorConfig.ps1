<#
.SYNOPSIS
    Restores Velociraptor server config from backup and fixes bind address

.DESCRIPTION
    Finds the most recent backup of server.config.yaml and restores it,
    then optionally fixes the GUI bind address to 0.0.0.0

.PARAMETER ServerPath
    Path to the Velociraptor Server installation directory
    Default: "C:\Program Files\Velociraptor Server"

.PARAMETER ConfigFile
    Name of the server configuration file
    Default: "server.config.yaml"

.PARAMETER FixBindAddress
    If specified, will update GUI bind_address to 0.0.0.0 after restore

.EXAMPLE
    .\Restore-VelociraptorConfig.ps1
    
.EXAMPLE
    .\Restore-VelociraptorConfig.ps1 -FixBindAddress
#>

param(
    [string]$ServerPath = "C:\Program Files\Velociraptor Server",
    [string]$ConfigFile = "server.config.yaml",
    [switch]$FixBindAddress
)

$configPath = Join-Path $ServerPath $ConfigFile

Write-Host "=== Restoring Velociraptor Configuration ===" -ForegroundColor Cyan
Write-Host ""

# Find backup files
Write-Host "Looking for backup files..." -ForegroundColor Yellow
$backupFiles = Get-ChildItem -Path $ServerPath -Filter "$ConfigFile.backup.*" -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending

if (-not $backupFiles) {
    Write-Host "ERROR: No backup files found!" -ForegroundColor Red
    Write-Host "Expected backup files matching: $ConfigFile.backup.*" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "You may need to manually fix the YAML file or regenerate the config." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found $($backupFiles.Count) backup file(s)" -ForegroundColor Green
$backupFiles | ForEach-Object {
    Write-Host "  - $($_.Name) (Last modified: $($_.LastWriteTime))" -ForegroundColor Gray
}

# Use most recent backup
$latestBackup = $backupFiles[0]
Write-Host ""
Write-Host "Restoring from: $($latestBackup.Name)" -ForegroundColor Yellow

try {
    # Restore the backup
    Copy-Item $latestBackup.FullName $configPath -Force
    Write-Host "Configuration restored successfully" -ForegroundColor Green
    
    # Verify the restored file is valid
    $testContent = Get-Content $configPath -Raw
    if (-not $testContent -or $testContent.Length -lt 100) {
        throw "Restored config file appears invalid or too small"
    }
    
    Write-Host "Configuration file validated" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to restore config: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Optionally fix bind address
if ($FixBindAddress) {
    Write-Host ""
    Write-Host "Fixing GUI bind address..." -ForegroundColor Yellow
    
    $configLines = Get-Content $configPath
    $inGuiSection = $false
    $updated = $false
    
    for ($i = 0; $i -lt $configLines.Count; $i++) {
        $line = $configLines[$i]
        
        # Detect GUI section start
        if ($line -match '^GUI:\s*$' -or $line -match '^GUI:') {
            $inGuiSection = $true
        }
        # Detect next top-level section
        elseif ($inGuiSection -and $line -match '^[A-Z][^:]*:\s*$' -and $line -notmatch '^\s') {
            $inGuiSection = $false
        }
        
        # Update bind_address in GUI section
        if ($inGuiSection -and $line -match '^\s+bind_address:\s*(.+)$') {
            $currentValue = $matches[1].Trim()
            if ($currentValue -eq '127.0.0.1' -or $currentValue -eq 'localhost') {
                $indent = if ($line -match '^(\s+)bind_address:') { $matches[1] } else { "  " }
                $configLines[$i] = "${indent}bind_address: 0.0.0.0"
                $updated = $true
                Write-Host "   Updated bind_address from $currentValue to 0.0.0.0" -ForegroundColor Green
            }
            elseif ($currentValue -eq '0.0.0.0') {
                Write-Host "   bind_address is already set to 0.0.0.0" -ForegroundColor Gray
            }
            break
        }
    }
    
    if ($updated) {
        try {
            $configLines | Set-Content $configPath -Encoding UTF8
            Write-Host "Configuration updated successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "ERROR: Failed to update bind address: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "=== Restore Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Verify config: Get-Content '$configPath' | Select-String -Pattern 'bind_address'" -ForegroundColor White
Write-Host "  2. Reinstall service: .\Fix-VelociraptorService.ps1" -ForegroundColor White
Write-Host ""

