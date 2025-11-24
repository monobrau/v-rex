<#
.SYNOPSIS
    Find Velociraptor client MSI file
#>

Write-Host "=== Finding Velociraptor Client MSI ===" -ForegroundColor Cyan
Write-Host ""

# Check common locations
$searchPaths = @(
    "C:\Packages",
    "C:\Program Files\Velociraptor Server",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Desktop",
    "C:\Temp",
    "C:\Windows\Temp"
)

Write-Host "Searching common locations..." -ForegroundColor Yellow
$found = $false

foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        $msiFiles = Get-ChildItem -Path $path -Filter "*velociraptor*.msi" -ErrorAction SilentlyContinue -Recurse -Depth 2
        if ($msiFiles) {
            Write-Host "Found MSI file(s) in: $path" -ForegroundColor Green
            $msiFiles | ForEach-Object {
                Write-Host "  - $($_.FullName)" -ForegroundColor Gray
                Write-Host "    Size: $([math]::Round($_.Length / 1MB, 2)) MB" -ForegroundColor Gray
                Write-Host "    Created: $($_.CreationTime)" -ForegroundColor Gray
                Write-Host "    Modified: $($_.LastWriteTime)" -ForegroundColor Gray
                $found = $true
            }
        }
    }
}

if (-not $found) {
    Write-Host "No MSI files found in common locations." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To create the MSI:" -ForegroundColor Yellow
    Write-Host "  1. Run: .\Manage-VelociraptorServer.ps1" -ForegroundColor White
    Write-Host "  2. In the GUI, go to 'Client Package Generation' section" -ForegroundColor White
    Write-Host "  3. Enter an output path (e.g., C:\Packages)" -ForegroundColor White
    Write-Host "  4. Click 'Create Client MSI'" -ForegroundColor White
    Write-Host "  5. The MSI will be created at: <output path>\velociraptor-client.msi" -ForegroundColor White
    Write-Host ""
    Write-Host "Or create it manually:" -ForegroundColor Yellow
    Write-Host "  cd 'C:\Program Files\Velociraptor Server'" -ForegroundColor White
    Write-Host "  .\velociraptor.exe --config server.config.yaml config repack --exe velociraptor.exe --msi C:\Packages\velociraptor-client.msi" -ForegroundColor White
}

Write-Host ""

