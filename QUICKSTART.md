# Quick Start Guide: V-Rex Velociraptor GPO Deployment

This guide will get you up and running with Velociraptor deployment in 15 minutes.

## Prerequisites Checklist

- [ ] Windows Server with Active Directory
- [ ] Administrative privileges
- [ ] RSAT tools installed
- [ ] Velociraptor MSI installer downloaded
- [ ] Velociraptor server deployed and accessible
- [ ] Network share created for evidence storage

## Step-by-Step Deployment

### 1. Prepare Your Environment (5 minutes)

#### Install RSAT Tools

```powershell
# On Windows Server
Install-WindowsFeature -Name GPMC

# On Windows 10/11
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
```

#### Download Velociraptor

```powershell
# Download from: https://github.com/Velocidex/velociraptor/releases
# Get the Windows MSI installer (e.g., velociraptor-v0.6.8-windows-amd64.msi)
```

#### Create Network Share

```powershell
# Example: Create evidence share
New-Item -Path "C:\VelociraptorEvidence" -ItemType Directory
New-SmbShare -Name "VelociraptorEvidence" -Path "C:\VelociraptorEvidence" -FullAccess "Administrators" -ReadAccess "Domain Computers"
```

### 2. Run the Deployment Tool (5 minutes)

#### Launch PowerShell as Administrator

```powershell
# Navigate to script location
cd C:\Scripts\v-rex

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process

# Run the tool
.\Deploy-VelociraptorGPO.ps1
```

#### Configure the GUI

Fill in the following fields:

| Field | Example Value |
|-------|---------------|
| **GPO Name** | `Deploy-Velociraptor-Forensics` |
| **Velociraptor MSI** | `C:\Downloads\velociraptor-v0.6.8-windows-amd64.msi` |
| **Server URL** | `https://velociraptor-server.domain.local:8000` |
| **Network Share** | `\\fileserver\VelociraptorEvidence` |
| **Target OU** | `OU=Workstations,DC=domain,DC=local` |
| **Deployment Method** | `Startup Script` |

#### Click "Create GPO"

Watch the output log for success messages.

### 3. Test the Deployment (5 minutes)

#### Create Test OU (Optional)

```powershell
# Create a test OU
New-ADOrganizationalUnit -Name "Velociraptor-Test" -Path "DC=domain,DC=local"

# Move a test computer
Move-ADObject -Identity "CN=TESTPC,CN=Computers,DC=domain,DC=local" `
              -TargetPath "OU=Velociraptor-Test,DC=domain,DC=local"
```

#### Force GPO Update on Test Computer

```powershell
# On the test computer, run as Administrator:
gpupdate /force

# Restart the computer
Restart-Computer
```

#### Verify Installation

After restart, check:

```powershell
# Check service is running
Get-Service -Name "Velociraptor"

# Check installation directory
Test-Path "$env:ProgramFiles\Velociraptor"

# Check configuration
Test-Path "$env:ProgramData\Velociraptor\client.config.yaml"

# Check evidence directory on network share
Test-Path "\\fileserver\VelociraptorEvidence\TESTPC"
```

Expected output:
```
Status   Name               DisplayName
------   ----               -----------
Running  Velociraptor       Velociraptor
```

## Common Configuration Scenarios

### Scenario 1: Deploy to All Workstations

```powershell
# In GUI, set Target OU to:
OU=Workstations,DC=domain,DC=local
```

### Scenario 2: Deploy to Specific Department

```powershell
# In GUI, set Target OU to:
OU=Finance,OU=Departments,DC=domain,DC=local
```

### Scenario 3: Deploy to Servers Only

```powershell
# In GUI, set Target OU to:
OU=Servers,DC=domain,DC=local
```

### Scenario 4: Multiple Velociraptor Servers

For different regions or departments:

1. Run the tool multiple times with different:
   - GPO Names: `Deploy-Velociraptor-US`, `Deploy-Velociraptor-EU`
   - Server URLs: `https://us-velo.domain.local:8000`, `https://eu-velo.domain.local:8000`
   - Network Shares: `\\us-share\Evidence`, `\\eu-share\Evidence`
   - Target OUs: `OU=US-Computers`, `OU=EU-Computers`

## Quick Troubleshooting

### GPO Not Applying

```powershell
# Check GPO status
gpresult /r

# View GPO details
Get-GPResultantSetOfPolicy -ReportType Html -Path C:\gpreport.html

# Force update
gpupdate /force /target:computer
```

### Service Not Starting

```powershell
# Check Windows Event Log
Get-EventLog -LogName Application -Source "Velociraptor" -Newest 10

# Check deployment log
Get-Content "\\fileserver\VelociraptorEvidence\Deployment\$env:COMPUTERNAME-deployment.log"
```

### Network Share Access Denied

```powershell
# Test share access
Test-Path "\\fileserver\VelociraptorEvidence"

# Check permissions
Get-SmbShareAccess -Name "VelociraptorEvidence"

# Add Domain Computers if missing
Grant-SmbShareAccess -Name "VelociraptorEvidence" -AccountName "Domain Computers" -AccessRight Change
```

## Monitoring Deployment

### Check How Many Computers Have Velociraptor

```powershell
# Count computer subdirectories in evidence share
(Get-ChildItem "\\fileserver\VelociraptorEvidence" -Directory |
    Where-Object { $_.Name -notmatch "Config|Deployment|Software" }).Count
```

### View Recent Deployments

```powershell
# Check deployment logs from last 24 hours
Get-ChildItem "\\fileserver\VelociraptorEvidence\Deployment" -Filter "*-deployment.log" |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-1) } |
    Select-Object Name, LastWriteTime
```

### Check GPO Application Status

```powershell
# Get computers where GPO is applied
Get-ADComputer -Filter * -SearchBase "OU=Workstations,DC=domain,DC=local" |
    ForEach-Object {
        $computer = $_.Name
        $applied = (Get-GPResultantSetOfPolicy -Computer $computer -ReportType Xml) -match "Deploy-Velociraptor"
        [PSCustomObject]@{
            Computer = $computer
            GPOApplied = $applied
        }
    }
```

## Next Steps

After successful deployment:

1. **Monitor Evidence Collection**
   - Check network share for incoming data
   - Review Velociraptor server console
   - Set up alerts for critical findings

2. **Configure Artifact Collection**
   - Customize which artifacts to collect
   - Set collection schedules
   - Configure hunting queries

3. **Set Up Retention Policies**
   - Implement data retention rules
   - Archive old evidence
   - Monitor disk space usage

4. **Train Your Team**
   - Educate IR team on Velociraptor usage
   - Document procedures
   - Practice incident response scenarios

5. **Expand Deployment**
   - After successful pilot, expand to more OUs
   - Deploy to servers if needed
   - Consider remote workers (VPN considerations)

## Rollback Procedure

If you need to remove the deployment:

```powershell
# Unlink GPO from OU
.\Remove-VelociraptorGPO.ps1 -GPOName "Deploy-Velociraptor-Forensics" `
                              -TargetOU "OU=Workstations,DC=domain,DC=local"

# Create uninstall script
.\Remove-VelociraptorGPO.ps1 -GPOName "Deploy-Velociraptor-Forensics" `
                              -CreateUninstallScript `
                              -NetworkShare "\\fileserver\VelociraptorEvidence"

# Remove GPO completely
.\Remove-VelociraptorGPO.ps1 -GPOName "Deploy-Velociraptor-Forensics" `
                              -RemoveGPO
```

## Getting Help

- **Check Logs**: `%TEMP%\VelociraptorGPODeployment.log`
- **Review Output**: GUI output window shows real-time progress
- **Velociraptor Docs**: https://docs.velociraptor.app/
- **AD GPO Cmdlets**: `Get-Help *-GPO*`

## Cheat Sheet

### Quick Commands

```powershell
# List all GPOs
Get-GPO -All | Select-Object DisplayName

# Check specific GPO
Get-GPO -Name "Deploy-Velociraptor-Forensics"

# View GPO links
Get-GPInheritance -Target "OU=Workstations,DC=domain,DC=local"

# Force client update
gpupdate /force

# Check service status
Get-Service Velociraptor

# View deployment logs
Get-Content "\\share\VelociraptorEvidence\Deployment\$env:COMPUTERNAME-deployment.log"

# Test network share
Test-Path "\\fileserver\VelociraptorEvidence"
```

## Success Criteria

Your deployment is successful when:

- ✅ GPO created and linked to target OU
- ✅ Test computer receives and applies GPO
- ✅ Velociraptor service installed and running
- ✅ Evidence directory created on network share
- ✅ Artifacts being collected and saved
- ✅ Velociraptor server shows connected clients
- ✅ No errors in deployment logs
- ✅ Network share accessible from endpoints

---

**Congratulations!** You've successfully deployed Velociraptor via GPO using V-Rex.

For detailed information, see [README.md](README.md)
