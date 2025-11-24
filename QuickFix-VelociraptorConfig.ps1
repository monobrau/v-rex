<#
.SYNOPSIS
    Quick fix for the corrupted GUI section in server.config.yaml

.DESCRIPTION
    Fixes the specific corruption where $10.0.0.0 appears instead of proper GUI section
#>

param(
    [string]$ConfigPath = "C:\Program Files\Velociraptor Server\server.config.yaml"
)

Write-Host "=== Quick Fix for Velociraptor Config ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Config file not found at: $ConfigPath" -ForegroundColor Red
    exit 1
}

# Create backup
$backupPath = "$ConfigPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item $ConfigPath $backupPath -Force
Write-Host "Backup created: $backupPath" -ForegroundColor Green

# Read the file
$configLines = Get-Content $ConfigPath
Write-Host "Read $($configLines.Count) lines" -ForegroundColor Gray

# Find and fix the corrupted GUI section
$fixed = $false
for ($i = 0; $i -lt $configLines.Count; $i++) {
    $line = $configLines[$i]
    
    # Find the corrupted line ($10.0.0.0)
    if ($line -match '^\$10\.0\.0\.0\s*$') {
        Write-Host "Found corrupted line at line $($i+1): $line" -ForegroundColor Yellow
        
        # Replace with proper GUI section
        Write-Host "Replacing with proper GUI section..." -ForegroundColor Yellow
        
        # Replace the corrupted line with GUI: header
        $configLines[$i] = "GUI:"
        
        # Insert bind_address line after GUI:
        $newLines = @("  bind_address: 0.0.0.0")
        $configLines = $configLines[0..$i] + $newLines + $configLines[($i+1)..($configLines.Count-1)]
        
        # Fix bind_port line if it exists and has wrong indentation
        $bindPortIndex = $i + 2
        if ($bindPortIndex -lt $configLines.Count) {
            if ($configLines[$bindPortIndex] -match '^\s+bind_port:\s*8889') {
                # Ensure it has proper 2-space indentation
                $configLines[$bindPortIndex] = "  bind_port: 8889"
                Write-Host "Fixed bind_port indentation" -ForegroundColor Gray
            }
        }
        
        $fixed = $true
        Write-Host "Fixed: Replaced corrupted line with proper GUI section" -ForegroundColor Green
        break
    }
}

if ($fixed) {
    Write-Host ""
    Write-Host "Writing fixed configuration..." -ForegroundColor Yellow
    $configLines | Set-Content $ConfigPath -Encoding UTF8
    Write-Host "Configuration file fixed successfully!" -ForegroundColor Green
    
    # Show the fixed section
    Write-Host ""
    Write-Host "Fixed GUI section:" -ForegroundColor Cyan
    $guiStart = -1
    for ($i = 0; $i -lt $configLines.Count; $i++) {
        if ($configLines[$i] -match '^GUI:') {
            $guiStart = $i
            break
        }
    }
    if ($guiStart -ge 0) {
        for ($i = $guiStart; $i -lt [Math]::Min($guiStart + 5, $configLines.Count); $i++) {
            Write-Host "  $($configLines[$i])" -ForegroundColor Gray
        }
    }
}
else {
    Write-Host ""
    Write-Host "Could not find the corrupted line pattern." -ForegroundColor Yellow
    Write-Host "The file may have a different corruption pattern." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next step: Run .\Fix-VelociraptorService.ps1" -ForegroundColor Yellow
Write-Host ""

