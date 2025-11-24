<#
.SYNOPSIS
    Fixes corrupted Velociraptor server.config.yaml file

.DESCRIPTION
    Attempts to fix common YAML syntax errors in the Velociraptor config file,
    particularly around the GUI bind_address section.

.PARAMETER ConfigPath
    Full path to the server.config.yaml file
    Default: "C:\Program Files\Velociraptor Server\server.config.yaml"

.EXAMPLE
    .\Fix-VelociraptorConfigYAML.ps1
    
.EXAMPLE
    .\Fix-VelociraptorConfigYAML.ps1 -ConfigPath "D:\Velociraptor\server.config.yaml"
#>

param(
    [string]$ConfigPath = "C:\Program Files\Velociraptor Server\server.config.yaml"
)

Write-Host "=== Fixing Velociraptor Configuration YAML ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Config file not found at: $ConfigPath" -ForegroundColor Red
    exit 1
}

# Create backup first
$backupPath = "$ConfigPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
try {
    Copy-Item $ConfigPath $backupPath -Force
    Write-Host "Backup created: $backupPath" -ForegroundColor Green
}
catch {
    Write-Host "WARNING: Could not create backup: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Read the file
Write-Host "Reading config file..." -ForegroundColor Yellow
try {
    $configLines = Get-Content $ConfigPath
    Write-Host "Read $($configLines.Count) lines" -ForegroundColor Gray
}
catch {
    Write-Host "ERROR: Failed to read config file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Show lines around line 65 for debugging
Write-Host ""
Write-Host "Checking around line 65 (where error was reported)..." -ForegroundColor Yellow
$startLine = [Math]::Max(0, 60)
$endLine = [Math]::Min($configLines.Count - 1, 70)
for ($i = $startLine; $i -le $endLine; $i++) {
    $lineNum = $i + 1
    $line = $configLines[$i]
    $marker = if ($lineNum -eq 65) { " <-- ERROR HERE" } else { "" }
    Write-Host "$lineNum`: $line$marker" -ForegroundColor $(if ($lineNum -eq 65) { 'Red' } else { 'Gray' })
}

Write-Host ""
Write-Host "Analyzing YAML structure..." -ForegroundColor Yellow

# Fix common issues
$fixed = $false
$inGuiSection = $false
$guiSectionStart = -1

for ($i = 0; $i -lt $configLines.Count; $i++) {
    $line = $configLines[$i]
    $lineNum = $i + 1
    
    # Detect GUI section
    if ($line -match '^GUI:\s*$' -or $line -match '^GUI:') {
        $inGuiSection = $true
        $guiSectionStart = $i
        Write-Host "Found GUI section starting at line $lineNum" -ForegroundColor Gray
    }
    
    # Detect end of GUI section (next top-level key)
    if ($inGuiSection -and $line -match '^[A-Z][a-zA-Z]*:\s*$' -and $line -notmatch '^GUI:' -and $line -notmatch '^\s') {
        $inGuiSection = $false
        Write-Host "GUI section ends at line $lineNum" -ForegroundColor Gray
    }
    
    # Fix common YAML issues in GUI section
    if ($inGuiSection) {
        # Fix missing colon after bind_address
        if ($line -match '^\s+bind_address\s+(.+)$' -and $line -notmatch ':') {
            Write-Host "Fixing line $lineNum : Missing colon after bind_address" -ForegroundColor Yellow
            $indent = if ($line -match '^(\s+)bind_address') { $matches[1] } else { "  " }
            $value = $matches[1].Trim()
            $configLines[$i] = "${indent}bind_address: $value"
            $fixed = $true
        }
        
        # Fix bind_address value
        if ($line -match '^\s+bind_address:\s*(.+)$') {
            $value = $matches[1].Trim()
            if ($value -eq '127.0.0.1' -or $value -eq 'localhost') {
                Write-Host "Updating bind_address on line $lineNum from $value to 0.0.0.0" -ForegroundColor Yellow
                $indent = if ($line -match '^(\s+)bind_address:') { $matches[1] } else { "  " }
                $configLines[$i] = "${indent}bind_address: 0.0.0.0"
                $fixed = $true
            }
        }
        
        # Fix malformed lines (missing colon, extra spaces, etc.)
        if ($lineNum -eq 65) {
            Write-Host "Examining problematic line 65..." -ForegroundColor Yellow
            
            # Check if it's a bind_address line without proper format
            if ($line -match '^\s*bind_address' -and $line -notmatch ':\s*') {
                Write-Host "Line 65 appears to be missing colon or has formatting issue" -ForegroundColor Red
                Write-Host "Current: $line" -ForegroundColor Red
                
                # Try to fix it
                if ($line -match '^\s*bind_address\s+(.+)$') {
                    $indent = if ($line -match '^(\s*)bind_address') { $matches[1] } else { "  " }
                    $value = $matches[1].Trim()
                    $configLines[$i] = "${indent}bind_address: $value"
                    Write-Host "Fixed to: $($configLines[$i])" -ForegroundColor Green
                    $fixed = $true
                }
                elseif ($line -match '^\s*bind_address:\s*$') {
                    # Missing value, add default
                    $indent = if ($line -match '^(\s*)bind_address:') { $matches[1] } else { "  " }
                    $configLines[$i] = "${indent}bind_address: 0.0.0.0"
                    Write-Host "Fixed to: $($configLines[$i])" -ForegroundColor Green
                    $fixed = $true
                }
            }
        }
    }
}

# Additional fixes for common YAML issues
Write-Host ""
Write-Host "Checking for other common YAML issues..." -ForegroundColor Yellow

for ($i = 0; $i -lt $configLines.Count; $i++) {
    $line = $configLines[$i]
    
    # Fix lines with multiple colons (often a sign of corruption)
    if ($line -match '::' -and $line -notmatch '::\s*$') {
        Write-Host "Fixing double colon on line $($i+1)" -ForegroundColor Yellow
        $configLines[$i] = $line -replace '::', ':'
        $fixed = $true
    }
    
    # Fix lines that are just whitespace with a colon
    if ($line -match '^\s+:\s*$') {
        Write-Host "Removing empty line with colon on line $($i+1)" -ForegroundColor Yellow
        $configLines[$i] = ""
        $fixed = $true
    }
}

if ($fixed) {
    Write-Host ""
    Write-Host "Writing fixed configuration..." -ForegroundColor Yellow
    try {
        $configLines | Set-Content $ConfigPath -Encoding UTF8
        Write-Host "Configuration file updated successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to write config file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Restoring from backup..." -ForegroundColor Yellow
        if (Test-Path $backupPath) {
            Copy-Item $backupPath $ConfigPath -Force
        }
        exit 1
    }
}
else {
    Write-Host ""
    Write-Host "No automatic fixes applied. The issue may require manual editing." -ForegroundColor Yellow
}

# Validate by trying to read it as YAML-like structure
Write-Host ""
Write-Host "Validating fixed configuration..." -ForegroundColor Yellow

# Check if GUI section looks correct
$guiSectionFound = $false
$bindAddressFound = $false
$inGuiSection = $false

for ($i = 0; $i -lt $configLines.Count; $i++) {
    $line = $configLines[$i]
    
    if ($line -match '^GUI:\s*$' -or $line -match '^GUI:') {
        $inGuiSection = $true
        $guiSectionFound = $true
    }
    
    if ($inGuiSection -and $line -match '^\s+bind_address:\s*(.+)$') {
        $bindAddressFound = $true
        $value = $matches[1].Trim()
        Write-Host "Found GUI bind_address: $value" -ForegroundColor Green
    }
    
    if ($inGuiSection -and $line -match '^[A-Z][a-zA-Z]*:\s*$' -and $line -notmatch '^GUI:') {
        $inGuiSection = $false
    }
}

if (-not $guiSectionFound) {
    Write-Host "WARNING: GUI section not found in config file" -ForegroundColor Yellow
}

if (-not $bindAddressFound) {
    Write-Host "WARNING: bind_address not found in GUI section" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Try validating: cd '$(Split-Path $ConfigPath -Parent)'; .\velociraptor.exe --config $(Split-Path $ConfigPath -Leaf) config show" -ForegroundColor White
Write-Host "  2. If validation fails, you may need to manually edit the file" -ForegroundColor White
Write-Host "  3. Or regenerate the config: .\velociraptor.exe config generate -i" -ForegroundColor White
Write-Host ""

