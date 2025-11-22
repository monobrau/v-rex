<#
.SYNOPSIS
    Removes Velociraptor GPO deployment and cleans up installations

.DESCRIPTION
    This script helps remove the Velociraptor GPO deployment created by
    Deploy-VelociraptorGPO.ps1. It can unlink GPOs, remove them, and
    optionally clean up Velociraptor installations from target computers.

.NOTES
    Author: V-Rex GPO Deployment Tool
    Version: 1.0
    Requires: Administrative privileges
#>

#Requires -Version 5.1
#Requires -Modules GroupPolicy
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true, HelpMessage = "Name of the GPO to remove")]
    [string]$GPOName,

    [Parameter(Mandatory = $false, HelpMessage = "OU to unlink from (leave empty to unlink from all)")]
    [string]$TargetOU,

    [Parameter(Mandatory = $false, HelpMessage = "Also remove the GPO after unlinking")]
    [switch]$RemoveGPO,

    [Parameter(Mandatory = $false, HelpMessage = "Create uninstall script for deployed computers")]
    [switch]$CreateUninstallScript,

    [Parameter(Mandatory = $false, HelpMessage = "Network share path for uninstall script")]
    [string]$NetworkShare
)

function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $Color
}

function Remove-VelociraptorDeployment {
    try {
        Write-ColorOutput "`n=== Velociraptor GPO Removal Tool ===" -Color Cyan
        Write-ColorOutput "GPO Name: $GPOName`n" -Color Yellow

        # Check if GPO exists
        $gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
        if (!$gpo) {
            Write-ColorOutput "GPO '$GPOName' not found." -Color Red
            return
        }

        Write-ColorOutput "Found GPO: $($gpo.DisplayName) (ID: $($gpo.Id))" -Color Green

        # Get all links
        $links = Get-ADObject -Filter "objectClass -eq 'organizationalUnit' -or objectClass -eq 'domain'" -Properties gPLink |
            Where-Object { $_.gPLink -like "*$($gpo.Id)*" }

        if ($links) {
            Write-ColorOutput "`nGPO is currently linked to:" -Color Yellow
            foreach ($link in $links) {
                Write-ColorOutput "  - $($link.DistinguishedName)" -Color White
            }

            # Unlink from specific OU or all
            if ($TargetOU) {
                Write-ColorOutput "`nUnlinking GPO from: $TargetOU" -Color Yellow
                try {
                    Remove-GPLink -Name $GPOName -Target $TargetOU -ErrorAction Stop
                    Write-ColorOutput "Successfully unlinked from $TargetOU" -Color Green
                }
                catch {
                    Write-ColorOutput "Failed to unlink from $TargetOU : $($_.Exception.Message)" -Color Red
                }
            }
            else {
                # Unlink from all
                Write-ColorOutput "`nUnlinking GPO from all locations..." -Color Yellow
                foreach ($link in $links) {
                    try {
                        Remove-GPLink -Name $GPOName -Target $link.DistinguishedName -ErrorAction Stop
                        Write-ColorOutput "Unlinked from: $($link.DistinguishedName)" -Color Green
                    }
                    catch {
                        Write-ColorOutput "Failed to unlink from $($link.DistinguishedName): $($_.Exception.Message)" -Color Red
                    }
                }
            }
        }
        else {
            Write-ColorOutput "`nGPO is not linked to any OUs." -Color Yellow
        }

        # Remove GPO if requested
        if ($RemoveGPO) {
            Write-ColorOutput "`nRemoving GPO..." -Color Yellow
            $confirm = Read-Host "Are you sure you want to delete the GPO '$GPOName'? (yes/no)"
            if ($confirm -eq 'yes') {
                try {
                    Remove-GPO -Name $GPOName -ErrorAction Stop
                    Write-ColorOutput "GPO removed successfully." -Color Green
                }
                catch {
                    Write-ColorOutput "Failed to remove GPO: $($_.Exception.Message)" -Color Red
                }
            }
            else {
                Write-ColorOutput "GPO removal cancelled." -Color Yellow
            }
        }

        # Create uninstall script if requested
        if ($CreateUninstallScript) {
            if ([string]::IsNullOrWhiteSpace($NetworkShare)) {
                Write-ColorOutput "`nNetwork share path required for uninstall script." -Color Red
            }
            else {
                New-UninstallScript -NetworkShare $NetworkShare
            }
        }

        Write-ColorOutput "`n=== Removal Process Complete ===" -Color Cyan
    }
    catch {
        Write-ColorOutput "`nError: $($_.Exception.Message)" -Color Red
    }
}

function New-UninstallScript {
    param([string]$NetworkShare)

    Write-ColorOutput "`nCreating uninstall script..." -Color Yellow

    $uninstallScript = @"
# Velociraptor Uninstall Script
# This script removes Velociraptor from target computers

`$ErrorActionPreference = 'Stop'
`$LogFile = "$NetworkShare\Deployment\`$env:COMPUTERNAME-uninstall.log"

function Write-UninstallLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path `$LogFile -Value "[`$timestamp] `$Message" -ErrorAction SilentlyContinue
}

try {
    Write-UninstallLog "Starting Velociraptor uninstallation on `$env:COMPUTERNAME"

    # Stop service
    `$service = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
    if (`$service) {
        if (`$service.Status -eq 'Running') {
            Write-UninstallLog "Stopping Velociraptor service..."
            Stop-Service -Name "Velociraptor" -Force
        }

        # Get product code from registry
        `$productCode = Get-WmiObject -Class Win32_Product |
            Where-Object { `$_.Name -like "*Velociraptor*" } |
            Select-Object -ExpandProperty IdentifyingNumber

        if (`$productCode) {
            Write-UninstallLog "Uninstalling Velociraptor (Product Code: `$productCode)..."
            `$arguments = "/x `$productCode /quiet /norestart /log `"$NetworkShare\Deployment\`$env:COMPUTERNAME-uninstall-msi.log`""
            `$process = Start-Process -FilePath "msiexec.exe" -ArgumentList `$arguments -Wait -PassThru

            if (`$process.ExitCode -eq 0 -or `$process.ExitCode -eq 1605) {
                Write-UninstallLog "Velociraptor uninstalled successfully"
            }
            else {
                Write-UninstallLog "ERROR: Uninstallation failed with exit code `$(`$process.ExitCode)"
            }
        }
        else {
            Write-UninstallLog "WARNING: Could not find Velociraptor product code"
        }
    }
    else {
        Write-UninstallLog "Velociraptor service not found - may already be uninstalled"
    }

    # Clean up directories
    `$dirs = @(
        "`$env:ProgramFiles\Velociraptor",
        "`$env:ProgramData\Velociraptor"
    )

    foreach (`$dir in `$dirs) {
        if (Test-Path `$dir) {
            Write-UninstallLog "Removing directory: `$dir"
            Remove-Item -Path `$dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-UninstallLog "Velociraptor uninstallation completed successfully"
}
catch {
    Write-UninstallLog "ERROR: `$(`$_.Exception.Message)"
    exit 1
}
"@

    $scriptPath = Join-Path $NetworkShare "Deployment\Uninstall-Velociraptor.ps1"

    try {
        $uninstallScript | Out-File -FilePath $scriptPath -Encoding UTF8 -Force
        Write-ColorOutput "Uninstall script created: $scriptPath" -Color Green
        Write-ColorOutput "`nTo deploy uninstall, you can:" -Color Yellow
        Write-ColorOutput "1. Create a new GPO with this script as a startup script" -Color White
        Write-ColorOutput "2. Run manually on target computers: powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`"" -Color White
        Write-ColorOutput "3. Use remote execution: Invoke-Command -ComputerName <computers> -FilePath `"$scriptPath`"" -Color White
    }
    catch {
        Write-ColorOutput "Failed to create uninstall script: $($_.Exception.Message)" -Color Red
    }
}

# Main execution
Remove-VelociraptorDeployment

Write-ColorOutput "`nNext Steps:" -Color Cyan
Write-ColorOutput "1. Force GPO update on affected computers: gpupdate /force" -Color White
Write-ColorOutput "2. Restart computers to ensure all policies are removed" -Color White
Write-ColorOutput "3. If you created an uninstall script, deploy it to remove Velociraptor from endpoints" -Color White
Write-ColorOutput "4. Clean up network share if no longer needed" -Color White
