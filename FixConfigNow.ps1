<#
.SYNOPSIS
    Direct fix for the $10.0.0.0 corruption in server.config.yaml
#>

$configPath = "C:\Program Files\Velociraptor Server\server.config.yaml"

Write-Host "Fixing corrupted config file..." -ForegroundColor Cyan

# Backup
$backup = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item $configPath $backup -Force
Write-Host "Backup: $backup" -ForegroundColor Green

# Read and fix
$content = Get-Content $configPath -Raw

# Replace the corrupted pattern
# Pattern: blank line, then $10.0.0.0, then blank line, then bind_port
# Replace with: blank line, then GUI:, then bind_address: 0.0.0.0, then bind_port
$content = $content -replace '(\r?\n)\$10\.0\.0\.0(\r?\n)(\r?\n)(\s+bind_port:)', '$1GUI:$2  bind_address: 0.0.0.0$3$4'

# Write back
$content | Set-Content $configPath -NoNewline -Encoding UTF8

Write-Host "Config file fixed!" -ForegroundColor Green
Write-Host ""
Write-Host "Verify the GUI section:" -ForegroundColor Yellow
Get-Content $configPath | Select-String -Pattern "GUI:|bind_address|bind_port" -Context 0,2

