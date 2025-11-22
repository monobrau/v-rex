# Troubleshooting Guide: V-Rex Velociraptor GPO Deployment

This guide covers common issues and their solutions when deploying Velociraptor via GPO.

## Table of Contents

- [Installation Issues](#installation-issues)
- [GPO Application Problems](#gpo-application-problems)
- [Network Share Issues](#network-share-issues)
- [Service Problems](#service-problems)
- [Evidence Collection Issues](#evidence-collection-issues)
- [Performance Issues](#performance-issues)
- [Diagnostic Commands](#diagnostic-commands)

---

## Installation Issues

### Problem: "MSI file not found" error

**Symptoms:**
- Deployment fails with file not found error
- Installation doesn't start

**Solutions:**

1. **Verify MSI path:**
   ```powershell
   Test-Path "C:\path\to\velociraptor.msi"
   ```

2. **Use UNC path instead of local path:**
   ```powershell
   # Instead of: C:\Installers\velociraptor.msi
   # Use: \\server\share\velociraptor.msi
   ```

3. **Check file permissions:**
   ```powershell
   Get-Acl "\\server\share\velociraptor.msi" | Format-List
   ```

### Problem: "Access Denied" during installation

**Symptoms:**
- MSI installation fails with error 5 (Access Denied)
- Deployment log shows permission errors

**Solutions:**

1. **Ensure SYSTEM account has access:**
   ```powershell
   # Startup scripts run as SYSTEM, test access as SYSTEM
   psexec -i -s powershell.exe
   Test-Path "\\server\share\velociraptor.msi"
   ```

2. **Add proper permissions:**
   ```powershell
   $acl = Get-Acl "\\server\share"
   $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
       "SYSTEM", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
   )
   $acl.SetAccessRule($rule)
   Set-Acl -Path "\\server\share" -AclObject $acl
   ```

### Problem: Installation fails silently

**Symptoms:**
- No errors shown but Velociraptor not installed
- MSI log shows errors

**Solutions:**

1. **Check MSI installation log:**
   ```powershell
   Get-Content "\\server\share\Deployment\COMPUTERNAME-install.log"
   ```

2. **Test MSI manually:**
   ```powershell
   msiexec /i "\\server\share\velociraptor.msi" /qn /l*v "C:\install-test.log"
   Get-Content "C:\install-test.log"
   ```

3. **Verify MSI is not corrupted:**
   ```powershell
   Get-FileHash "\\server\share\velociraptor.msi" -Algorithm SHA256
   # Compare with hash from download source
   ```

---

## GPO Application Problems

### Problem: GPO not applying to computers

**Symptoms:**
- Computers not receiving GPO settings
- `gpresult` doesn't show the GPO

**Solutions:**

1. **Verify GPO is linked:**
   ```powershell
   Get-GPInheritance -Target "OU=Workstations,DC=domain,DC=local" |
       Select-Object -ExpandProperty GpoLinks
   ```

2. **Check GPO link is enabled:**
   ```powershell
   (Get-GPInheritance -Target "OU=Workstations,DC=domain,DC=local").GpoLinks |
       Where-Object { $_.DisplayName -eq "Deploy-Velociraptor-Forensics" } |
       Select-Object DisplayName, Enabled, Enforced
   ```

3. **Verify GPO status:**
   ```powershell
   Get-GPO -Name "Deploy-Velociraptor-Forensics" |
       Select-Object DisplayName, GpoStatus
   ```

4. **Force replication:**
   ```powershell
   # On domain controller
   repadmin /syncall /AdeP
   ```

5. **Force GPO update on client:**
   ```powershell
   gpupdate /force /target:computer
   ```

### Problem: GPO shows in gpresult but doesn't execute

**Symptoms:**
- `gpresult` shows GPO applied
- Startup script doesn't run

**Solutions:**

1. **Check script execution policy:**
   ```powershell
   Get-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\PowerShell" |
       Select-Object ExecutionPolicy, EnableScripts
   ```

2. **Verify startup script is configured:**
   ```powershell
   Get-GPOReport -Name "Deploy-Velociraptor-Forensics" -ReportType Html -Path "C:\gpo-report.html"
   # Open HTML file and check Startup Scripts section
   ```

3. **Check Group Policy event logs:**
   ```powershell
   Get-WinEvent -LogName "Microsoft-Windows-GroupPolicy/Operational" -MaxEvents 50 |
       Where-Object { $_.Message -like "*Velociraptor*" }
   ```

### Problem: "Waiting for Group Policy Scripts" delay

**Symptoms:**
- Computer startup takes very long
- Stuck waiting for scripts

**Solutions:**

1. **Configure script timeout:**
   ```powershell
   # Set via GPO: Computer Configuration > Administrative Templates >
   # System > Scripts > Maximum wait time for Group Policy scripts
   # Recommended: 300 seconds (5 minutes)
   ```

2. **Optimize deployment script:**
   - Remove unnecessary waiting
   - Add timeout parameters
   - Use background jobs for long operations

---

## Network Share Issues

### Problem: Cannot access network share

**Symptoms:**
- "Network path not found" errors
- "Access Denied" to network share

**Solutions:**

1. **Test share connectivity:**
   ```powershell
   Test-Path "\\server\VelociraptorEvidence"
   Test-NetConnection -ComputerName server -Port 445
   ```

2. **Check SMB configuration:**
   ```powershell
   Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol
   ```

3. **Verify share permissions:**
   ```powershell
   Get-SmbShareAccess -Name "VelociraptorEvidence"
   Get-SmbShare -Name "VelociraptorEvidence"
   ```

4. **Add Domain Computers to share:**
   ```powershell
   Grant-SmbShareAccess -Name "VelociraptorEvidence" `
       -AccountName "Domain Computers" `
       -AccessRight Change -Force
   ```

5. **Check NTFS permissions:**
   ```powershell
   Get-Acl "\\server\VelociraptorEvidence" | Format-List
   ```

### Problem: Network share full or running out of space

**Symptoms:**
- Write errors to network share
- Evidence collection failing

**Solutions:**

1. **Check disk space:**
   ```powershell
   Get-PSDrive | Where-Object { $_.Name -eq "V" } | Select-Object Used, Free
   # Or directly check
   Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='D:'" |
       Select-Object DeviceID, FreeSpace, Size
   ```

2. **Implement quota management:**
   ```powershell
   # Set quota per computer folder
   fsutil quota modify D:\VelociraptorEvidence 10737418240 5368709120 # 10GB limit, 5GB warning
   ```

3. **Archive old evidence:**
   ```powershell
   # Move evidence older than 90 days
   Get-ChildItem "\\server\VelociraptorEvidence" -Directory |
       Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } |
       ForEach-Object {
           Move-Item -Path $_.FullName -Destination "\\archive\OldEvidence"
       }
   ```

---

## Service Problems

### Problem: Velociraptor service won't start

**Symptoms:**
- Service status shows "Stopped"
- Service fails to start with error

**Solutions:**

1. **Check service status and error:**
   ```powershell
   Get-Service -Name "Velociraptor" | Select-Object *
   Get-EventLog -LogName Application -Source "Velociraptor" -Newest 10
   ```

2. **Verify configuration file:**
   ```powershell
   Test-Path "$env:ProgramData\Velociraptor\client.config.yaml"
   Get-Content "$env:ProgramData\Velociraptor\client.config.yaml"
   ```

3. **Check service account:**
   ```powershell
   Get-WmiObject Win32_Service -Filter "Name='Velociraptor'" |
       Select-Object Name, StartMode, State, StartName
   ```

4. **Manually start service with verbose logging:**
   ```powershell
   # Stop service if running
   Stop-Service -Name "Velociraptor" -Force

   # Start manually to see errors
   & "$env:ProgramFiles\Velociraptor\velociraptor.exe" `
       --config "$env:ProgramData\Velociraptor\client.config.yaml" client -v
   ```

5. **Reinstall service:**
   ```powershell
   # Uninstall
   & "$env:ProgramFiles\Velociraptor\velociraptor.exe" service remove

   # Reinstall
   & "$env:ProgramFiles\Velociraptor\velociraptor.exe" `
       --config "$env:ProgramData\Velociraptor\client.config.yaml" service install
   ```

### Problem: Service crashes or stops unexpectedly

**Symptoms:**
- Service was running but now stopped
- Crash dumps or error logs

**Solutions:**

1. **Check Windows Event Logs:**
   ```powershell
   Get-EventLog -LogName Application -After (Get-Date).AddDays(-1) |
       Where-Object { $_.Source -like "*Velociraptor*" -or $_.Source -eq "Application Error" }
   ```

2. **Enable crash dumps:**
   ```powershell
   # Configure Windows Error Reporting
   $wer = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
   New-ItemProperty -Path "$wer\LocalDumps" -Name DumpFolder -Value "C:\CrashDumps" -Force
   New-ItemProperty -Path "$wer\LocalDumps" -Name DumpType -Value 2 -Force
   ```

3. **Configure service recovery:**
   ```powershell
   sc.exe failure Velociraptor reset= 86400 actions= restart/60000/restart/60000/restart/60000
   ```

---

## Evidence Collection Issues

### Problem: No evidence being collected

**Symptoms:**
- Computer folder exists but empty
- No logs or artifacts

**Solutions:**

1. **Check Velociraptor server connection:**
   ```powershell
   Test-NetConnection -ComputerName velociraptor-server.domain.local -Port 8000
   ```

2. **Verify client is registered with server:**
   - Check Velociraptor server GUI
   - Look for client in client list

3. **Check client logs:**
   ```powershell
   Get-Content "\\server\VelociraptorEvidence\$env:COMPUTERNAME\Logs\*.log"
   ```

4. **Test manual artifact collection:**
   ```powershell
   # On client, run manual collection
   & "$env:ProgramFiles\Velociraptor\velociraptor.exe" `
       --config "$env:ProgramData\Velociraptor\client.config.yaml" `
       artifacts collect Windows.KapeFiles.Targets
   ```

### Problem: Some artifacts not collecting

**Symptoms:**
- Some data collected but not all expected artifacts
- Specific artifact collection failing

**Solutions:**

1. **Check artifact requirements:**
   - Verify artifact supports current OS version
   - Check if artifact requires admin privileges
   - Ensure required tools/dependencies present

2. **Review artifact logs:**
   ```powershell
   # Check for artifact-specific errors in logs
   Select-String -Path "\\server\VelociraptorEvidence\$env:COMPUTERNAME\Logs\*.log" `
       -Pattern "error|failed|denied"
   ```

3. **Test artifact manually:**
   ```powershell
   & "$env:ProgramFiles\Velociraptor\velociraptor.exe" `
       --config "$env:ProgramData\Velociraptor\client.config.yaml" `
       artifacts collect Windows.System.ProcessInfo -v
   ```

---

## Performance Issues

### Problem: High CPU or memory usage

**Symptoms:**
- Velociraptor using excessive resources
- Computer performance degraded

**Solutions:**

1. **Check current resource usage:**
   ```powershell
   Get-Process -Name "velociraptor" |
       Select-Object CPU, WorkingSet, Handles, StartTime
   ```

2. **Adjust configuration limits:**
   Edit `client.config.yaml`:
   ```yaml
   Client:
     max_poll: 60        # Increase poll interval
     max_poll_std: 30    # Add randomization
   ```

3. **Limit concurrent artifact collection:**
   ```yaml
   Client:
     max_parallel_artifacts: 2  # Reduce from default
   ```

4. **Configure CPU throttling:**
   ```powershell
   # Limit process priority
   $process = Get-Process -Name "velociraptor"
   $process.PriorityClass = "BelowNormal"
   ```

### Problem: Slow artifact collection

**Symptoms:**
- Collections taking very long time
- Network transfer slow

**Solutions:**

1. **Check network bandwidth:**
   ```powershell
   Test-NetConnection -ComputerName velociraptor-server.domain.local -Port 8000
   # Monitor network usage
   Get-NetAdapterStatistics
   ```

2. **Optimize network share access:**
   - Use local caching
   - Implement DFS if available
   - Check network latency

3. **Adjust upload limits:**
   ```yaml
   Client:
     max_upload_rate: 5000000  # 5MB/s instead of unlimited
   ```

---

## Diagnostic Commands

### Comprehensive Health Check Script

```powershell
# Velociraptor Deployment Health Check
# Run on client computer

Write-Host "=== Velociraptor Deployment Health Check ===" -ForegroundColor Cyan

# 1. Check service
Write-Host "`n[1] Service Status:" -ForegroundColor Yellow
Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue | Format-Table

# 2. Check installation
Write-Host "`n[2] Installation:" -ForegroundColor Yellow
$paths = @(
    "$env:ProgramFiles\Velociraptor",
    "$env:ProgramData\Velociraptor",
    "$env:ProgramData\Velociraptor\client.config.yaml"
)
foreach ($path in $paths) {
    $exists = Test-Path $path
    Write-Host "  $path : $exists" -ForegroundColor $(if($exists){"Green"}else{"Red"})
}

# 3. Check network share
Write-Host "`n[3] Network Share Access:" -ForegroundColor Yellow
$sharePath = "\\server\VelociraptorEvidence"  # Update as needed
$accessible = Test-Path $sharePath
Write-Host "  $sharePath : $accessible" -ForegroundColor $(if($accessible){"Green"}else{"Red"})

if ($accessible) {
    $computerPath = Join-Path $sharePath $env:COMPUTERNAME
    $computerPathExists = Test-Path $computerPath
    Write-Host "  $computerPath : $computerPathExists" -ForegroundColor $(if($computerPathExists){"Green"}else{"Red"})
}

# 4. Check server connectivity
Write-Host "`n[4] Server Connectivity:" -ForegroundColor Yellow
$serverUrl = "velociraptor-server.domain.local"  # Update as needed
$testConn = Test-NetConnection -ComputerName $serverUrl -Port 8000 -WarningAction SilentlyContinue
Write-Host "  TCP 8000: $($testConn.TcpTestSucceeded)" -ForegroundColor $(if($testConn.TcpTestSucceeded){"Green"}else{"Red"})

# 5. Check recent logs
Write-Host "`n[5] Recent Logs:" -ForegroundColor Yellow
$logPath = "\\server\VelociraptorEvidence\$env:COMPUTERNAME\Logs"  # Update as needed
if (Test-Path $logPath) {
    Get-ChildItem $logPath -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 3 |
        ForEach-Object {
            Write-Host "  $($_.Name) - $($_.LastWriteTime)" -ForegroundColor Green
        }
}
else {
    Write-Host "  Log path not found: $logPath" -ForegroundColor Red
}

# 6. Check GPO application
Write-Host "`n[6] GPO Application:" -ForegroundColor Yellow
$gpResult = gpresult /r /scope:computer 2>&1 | Select-String "Velociraptor"
if ($gpResult) {
    Write-Host "  GPO Applied: YES" -ForegroundColor Green
}
else {
    Write-Host "  GPO Applied: NO" -ForegroundColor Red
}

# 7. Check event logs
Write-Host "`n[7] Recent Errors:" -ForegroundColor Yellow
Get-EventLog -LogName Application -After (Get-Date).AddHours(-24) -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -like "*Velociraptor*" -and $_.EntryType -eq "Error" } |
    Select-Object -First 5 |
    ForEach-Object {
        Write-Host "  $($_.TimeGenerated): $($_.Message)" -ForegroundColor Red
    }

Write-Host "`n=== Health Check Complete ===" -ForegroundColor Cyan
```

### GPO Verification Script

```powershell
# Verify GPO deployment
# Run on domain controller

$gpoName = "Deploy-Velociraptor-Forensics"

Write-Host "=== GPO Verification: $gpoName ===" -ForegroundColor Cyan

# Check GPO exists
$gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if ($gpo) {
    Write-Host "`n[OK] GPO exists" -ForegroundColor Green
    Write-Host "  ID: $($gpo.Id)" -ForegroundColor Gray
    Write-Host "  Status: $($gpo.GpoStatus)" -ForegroundColor Gray
}
else {
    Write-Host "`n[ERROR] GPO not found!" -ForegroundColor Red
    exit
}

# Check links
Write-Host "`n[*] GPO Links:" -ForegroundColor Yellow
$allOUs = Get-ADOrganizationalUnit -Filter * -Properties gPLink
$linkedOUs = $allOUs | Where-Object { $_.gPLink -like "*$($gpo.Id)*" }

if ($linkedOUs) {
    foreach ($ou in $linkedOUs) {
        Write-Host "  - $($ou.DistinguishedName)" -ForegroundColor Green
    }
}
else {
    Write-Host "  [WARNING] GPO not linked to any OUs" -ForegroundColor Yellow
}

# Check settings
Write-Host "`n[*] GPO Settings:" -ForegroundColor Yellow
$report = Get-GPOReport -Name $gpoName -ReportType Xml
if ($report -match "Deploy-Velociraptor\.ps1") {
    Write-Host "  [OK] Startup script configured" -ForegroundColor Green
}
else {
    Write-Host "  [WARNING] Startup script not found in GPO" -ForegroundColor Yellow
}

Write-Host "`n=== Verification Complete ===" -ForegroundColor Cyan
```

---

## Getting Additional Help

If issues persist:

1. **Enable detailed logging** in Velociraptor configuration
2. **Collect diagnostics** using scripts above
3. **Review Velociraptor documentation**: https://docs.velociraptor.app/
4. **Check Velociraptor community forums**: https://github.com/Velocidex/velociraptor/discussions
5. **Review Windows Event Logs** for system-level errors
6. **Test in isolated environment** to isolate the issue

## Common Error Codes

| Error Code | Description | Solution |
|------------|-------------|----------|
| 5 | Access Denied | Check permissions, run as admin |
| 53 | Network path not found | Verify share exists and is accessible |
| 1067 | Process terminated unexpectedly | Check service configuration |
| 1053 | Service timeout | Increase service timeout |
| 1326 | Logon failure | Verify service account credentials |
| 2250 | Network connection not found | Check network connectivity |

---

For more information, see [README.md](README.md) and [QUICKSTART.md](QUICKSTART.md).
