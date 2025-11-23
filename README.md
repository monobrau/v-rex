# V-Rex: Velociraptor GPO Deployment Tool

A complete Windows PowerShell GUI solution for deploying and managing Velociraptor digital forensics and incident response infrastructure via Group Policy Objects (GPO) on Windows Server environments.

## Overview

V-Rex provides end-to-end automation for Velociraptor deployment, from server installation to client deployment via Group Policy. The suite includes:

- **Server Installation**: Automated Velociraptor server setup with GUI
- **Server Management**: GUI-based server administration and monitoring
- **GPO Deployment**: Automated client deployment via Group Policy
- **Evidence Collection**: Centralized evidence storage on network shares
- **Client Package Creation**: Automated MSI generation for deployment

## Tools Included

### 1. Install-VelociraptorServer.ps1
GUI tool for installing and configuring a Velociraptor server including:
- Interactive server configuration wizard
- Automatic service installation
- Firewall rule configuration
- Initial admin user creation
- SSL certificate setup

### 2. Manage-VelociraptorServer.ps1
Server management console providing:
- Service control (start, stop, restart)
- User management with role-based access
- Client MSI package generation
- Server status monitoring
- Configuration editing

### 3. Deploy-VelociraptorGPO.ps1
GPO deployment tool for client rollout:
- GPO creation and configuration
- Velociraptor client configuration generation
- Automated deployment script creation
- Network share setup for evidence collection
- OU targeting for controlled deployment

### 4. Remove-VelociraptorGPO.ps1
Cleanup and removal tool:
- GPO unlinking and removal
- Client uninstallation script generation
- Safe removal procedures

## Features

- **Complete Solution**: Server to client deployment in one package
- **Graphical User Interface**: Easy-to-use Windows Forms GUIs for all tools
- **Automated Setup**: Minimal manual configuration required
- **Evidence Collection**: Automatically saves forensic evidence to network shares
- **Flexible Deployment**: Supports startup script and software installation methods
- **Comprehensive Logging**: Real-time output and persistent log files
- **OU Targeting**: Link GPOs to specific Organizational Units
- **Role-Based Access**: Multiple user roles for server access control

## Prerequisites

### System Requirements

- **Operating System**: Windows Server 2012 R2 or later
- **PowerShell**: Version 5.1 or later
- **Administrative Privileges**: Script must run as Administrator
- **Active Directory**: Domain environment with AD DS
- **RSAT Tools**: Remote Server Administration Tools installed

### Required PowerShell Modules

- `GroupPolicy` (part of RSAT)
- `ActiveDirectory` (optional, for OU browsing)

### Installation of RSAT

On Windows Server:
```powershell
# Install RSAT tools
Install-WindowsFeature -Name GPMC
```

On Windows 10/11:
```powershell
# Add RSAT Group Policy Management Tools
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
```

### Velociraptor Requirements

- Velociraptor executable (download from GitHub releases)
- Network connectivity for server-client communication

## Quick Start

### Complete Deployment Workflow

1. **Install Velociraptor Server** (see [SERVER_SETUP.md](SERVER_SETUP.md))
2. **Create Client MSI Package** using server management tool
3. **Deploy via GPO** to domain computers
4. **Monitor** client connections and evidence collection

## Installation

### 1. Download V-Rex Tools

Clone or download all scripts to your Windows Server:

```powershell
# If using git
git clone https://github.com/yourrepo/v-rex.git
cd v-rex

# Or download and extract ZIP file
# Verify GroupPolicy module is available
Get-Module -ListAvailable GroupPolicy

# If not available, install RSAT
Install-WindowsFeature -Name GPMC
```

## Usage

### Step 1: Install Velociraptor Server

Before deploying clients, you need a Velociraptor server. See [SERVER_SETUP.md](SERVER_SETUP.md) for detailed instructions.

**Quick Server Installation:**

```powershell
# Download Velociraptor from GitHub releases first
# https://github.com/Velocidex/velociraptor/releases

# Run server installation tool
.\Install-VelociraptorServer.ps1

# Follow GUI prompts to:
# - Set installation path
# - Configure hostname and ports
# - Set admin credentials
# - Generate configuration
```

After installation, use the management console:

```powershell
.\Manage-VelociraptorServer.ps1

# Create client MSI package for deployment
# Manage users and server settings
```

### Step 2: Deploy Clients via GPO

1. **Open PowerShell as Administrator**:
   ```powershell
   # Right-click PowerShell and select "Run as Administrator"
   ```

2. **Set Execution Policy** (if needed):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

3. **Run the Deployment Script**:
   ```powershell
   .\Deploy-VelociraptorGPO.ps1
   ```

### GUI Configuration

The tool presents a GUI with the following fields:

#### 1. GPO Name
- **Description**: Name for the new Group Policy Object
- **Default**: `Deploy-Velociraptor-Forensics`
- **Example**: `Deploy-Velociraptor-IR-Team`

#### 2. Velociraptor MSI
- **Description**: Path to Velociraptor MSI installer
- **Format**: Local or UNC path
- **Example**: `\\server\software\velociraptor-client.msi`
- **Action**: Click "Browse..." to select the file

**⚠️ CRITICAL:** The MSI **MUST** be generated using `Manage-VelociraptorServer.ps1`. Do NOT use:
- Generic Velociraptor MSIs from velociraptor.app
- MSIs from other sources
- Manually created MSI packages

The server-generated MSI contains embedded client configuration and SSL certificates required for authentication. Using any other MSI will result in connection failures.

#### 3. Server URL
- **Description**: Velociraptor server URL
- **Format**: `https://hostname:port`
- **Default**: `https://velociraptor.domain.local:8000`
- **Example**: `https://forensics-server.contoso.com:8000`

#### 4. Network Share
- **Description**: UNC path for evidence storage
- **Format**: `\\server\share`
- **Default**: `\\server\VelociraptorEvidence`
- **Example**: `\\forensics-nas\Evidence`
- **Note**: Each computer will have a subdirectory: `\\server\share\COMPUTERNAME`

#### 5. Target OU (Optional)
- **Description**: Organizational Unit to link the GPO
- **Format**: Distinguished Name
- **Example**: `OU=Workstations,DC=contoso,DC=com`
- **Action**: Click "Refresh" to populate available OUs

#### 6. Deployment Method
- **Startup Script**: Deploys via GPO startup script (recommended)
- **Software Installation**: Uses GPO software installation policy

### Workflow

1. **Fill in all required fields**
2. **Click "Create GPO"**
3. **Monitor the output log** for progress
4. **Verify success message**
5. **Test on a pilot machine** before wide deployment

## What the Tool Creates

### Directory Structure

The tool creates the following structure on your network share:

```
\\server\VelociraptorEvidence\
├── Config\
│   └── client.config.yaml          # Velociraptor client configuration
├── Deployment\
│   ├── Deploy-Velociraptor.ps1     # Deployment script
│   └── COMPUTERNAME-deployment.log # Per-computer deployment logs
├── Software\
│   └── velociraptor-*.msi          # Copied MSI installer
└── COMPUTERNAME\                   # Per-computer evidence directories
    ├── Logs\                       # Velociraptor logs
    └── [Evidence files]            # Collected forensic artifacts
```

### Group Policy Object

The created GPO includes:

- **Computer Configuration > Policies > Windows Settings > Scripts > Startup**
  - Deployment script that installs and configures Velociraptor

- **Computer Configuration > Policies > Administrative Templates**
  - PowerShell execution policy settings
  - Script execution permissions

### Velociraptor Configuration

Auto-generated `client.config.yaml` includes:

- Server connection settings
- Output directory configuration (network share)
- Local buffer settings
- Service installation parameters
- Logging configuration
- Auto-execution settings for artifact collection

## Network Share Permissions

The network share must have appropriate permissions:

### Recommended Permissions

- **Domain Computers**: Read & Execute, List folder contents, Read
- **Domain Admins**: Full Control
- **Forensics Team**: Modify (for evidence review)

### PowerShell to Set Permissions

```powershell
# Example: Grant permissions to Domain Computers
$sharePath = "\\server\VelociraptorEvidence"
$acl = Get-Acl $sharePath

# Add Domain Computers with Read/Write
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "DOMAIN\Domain Computers",
    "ReadAndExecute, Write",
    "ContainerInherit, ObjectInherit",
    "None",
    "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl -Path $sharePath -AclObject $acl
```

## Testing the Deployment

### Test on a Single Computer

1. **Create a test OU**:
   ```powershell
   New-ADOrganizationalUnit -Name "Velociraptor-Test" -Path "DC=contoso,DC=com"
   ```

2. **Move a test computer to the OU**:
   ```powershell
   Move-ADObject -Identity "CN=TESTPC,CN=Computers,DC=contoso,DC=com" `
                 -TargetPath "OU=Velociraptor-Test,DC=contoso,DC=com"
   ```

3. **Link the GPO** (if not done via tool):
   ```powershell
   New-GPLink -Name "Deploy-Velociraptor-Forensics" `
              -Target "OU=Velociraptor-Test,DC=contoso,DC=com"
   ```

4. **Force GPO update on test computer**:
   ```powershell
   # On the test computer
   gpupdate /force
   ```

5. **Restart the test computer** to trigger startup script

6. **Verify installation**:
   ```powershell
   # On the test computer
   Get-Service -Name "Velociraptor"
   Test-Path "$env:ProgramFiles\Velociraptor"
   ```

7. **Check evidence directory**:
   ```powershell
   # Check if computer-specific directory was created
   Test-Path "\\server\VelociraptorEvidence\TESTPC"
   ```

## Troubleshooting

### GPO Not Applying

**Check GPO Link**:
```powershell
Get-GPInheritance -Target "OU=YourOU,DC=domain,DC=com"
```

**Check GPO Status**:
```powershell
Get-GPO -Name "Deploy-Velociraptor-Forensics" | Select-Object DisplayName, GpoStatus
```

**Force Update on Client**:
```powershell
gpupdate /force /target:computer
```

### Installation Failures

**Check Deployment Log**:
```powershell
# On network share
Get-Content "\\server\VelociraptorEvidence\Deployment\COMPUTERNAME-deployment.log"
```

**Check MSI Install Log**:
```powershell
Get-Content "\\server\VelociraptorEvidence\Deployment\COMPUTERNAME-install.log"
```

**Verify Network Share Access**:
```powershell
# On client computer
Test-Path "\\server\VelociraptorEvidence"
```

### Service Not Starting

**Check Service Status**:
```powershell
Get-Service -Name "Velociraptor" | Select-Object *
```

**Check Event Logs**:
```powershell
Get-EventLog -LogName Application -Source "Velociraptor" -Newest 10
```

**Verify Configuration**:
```powershell
Test-Path "$env:ProgramData\Velociraptor\client.config.yaml"
Get-Content "$env:ProgramData\Velociraptor\client.config.yaml"
```

### Network Share Access Issues

**Test Share Access**:
```powershell
# Run as SYSTEM account (like startup scripts do)
psexec -i -s powershell.exe
Test-Path "\\server\VelociraptorEvidence"
```

**Check SMB Settings**:
```powershell
Get-SmbShare
Get-SmbShareAccess -Name "VelociraptorEvidence"
```

## Security Considerations

### Least Privilege

- Use a dedicated service account for Velociraptor if possible
- Limit network share access to necessary computers
- Implement share-level and NTFS permissions

### Network Segmentation

- Consider deploying Velociraptor server on isolated network
- Use firewall rules to restrict server access
- Implement certificate-based authentication

### Evidence Integrity

- Enable auditing on evidence share
- Implement write-once permissions where possible
- Regular backup of evidence data
- Hash verification of collected artifacts

### Monitoring

Monitor for:
- Unauthorized GPO modifications
- Failed deployment attempts
- Unusual evidence access patterns
- Service failures or crashes

```powershell
# Example: Monitor GPO modifications
Get-EventLog -LogName Security -InstanceId 5136,5137,5138,5139 |
    Where-Object { $_.Message -like "*Velociraptor*" }
```

## Maintenance

### Updating Velociraptor

To update to a new version:

1. Test new version in lab environment
2. Update MSI path in GPO or network share
3. Modify deployment script if needed
4. Deploy to pilot group first
5. Monitor for issues
6. Roll out to production

### GPO Management

**Backup GPO**:
```powershell
Backup-GPO -Name "Deploy-Velociraptor-Forensics" -Path "C:\GPO-Backups"
```

**Export GPO Settings**:
```powershell
Get-GPOReport -Name "Deploy-Velociraptor-Forensics" -ReportType Html `
              -Path "C:\Reports\Velociraptor-GPO.html"
```

**Remove GPO** (if needed):
```powershell
# Unlink first
Remove-GPLink -Name "Deploy-Velociraptor-Forensics" `
              -Target "OU=YourOU,DC=domain,DC=com"

# Then remove
Remove-GPO -Name "Deploy-Velociraptor-Forensics"
```

## Log Files

The tool creates several log files:

- **Main Tool Log**: `%TEMP%\VelociraptorGPODeployment.log`
- **Deployment Logs**: `\\server\share\Deployment\COMPUTERNAME-deployment.log`
- **MSI Install Logs**: `\\server\share\Deployment\COMPUTERNAME-install.log`
- **Velociraptor Logs**: `\\server\share\COMPUTERNAME\Logs\`

## Advanced Configuration

### Custom Velociraptor Configuration

To customize the Velociraptor configuration:

1. Edit the `New-VelociraptorConfig` function in the script
2. Modify YAML structure as needed
3. Add custom artifacts or hunting queries
4. Configure collection schedules

### Multiple Deployment Scenarios

For different computer groups:

1. Create multiple GPOs with different names
2. Link each to specific OUs
3. Customize configuration per group
4. Use different network share paths if needed

Example:
- `Deploy-Velociraptor-Servers` → OU=Servers
- `Deploy-Velociraptor-Workstations` → OU=Workstations
- `Deploy-Velociraptor-Critical` → OU=Critical-Systems

## Best Practices

1. **Test First**: Always test in lab before production
2. **Pilot Deployment**: Deploy to small group first
3. **Monitor Closely**: Watch logs and service status
4. **Document Everything**: Keep records of configurations
5. **Regular Audits**: Review GPO settings periodically
6. **Backup GPOs**: Regular backups before changes
7. **Network Share Health**: Monitor disk space and permissions
8. **Update Strategy**: Plan for version updates
9. **Incident Response Plan**: Have rollback procedures ready
10. **Team Training**: Ensure team knows how to use Velociraptor

## Compliance and Legal

- Ensure deployment complies with organizational policies
- Obtain necessary approvals for endpoint monitoring
- Document legal authority for evidence collection
- Maintain chain of custody for forensic evidence
- Follow data retention policies
- Respect privacy regulations (GDPR, etc.)

## Support and Resources

### Velociraptor Documentation

- Official Documentation: https://docs.velociraptor.app/
- GitHub Repository: https://github.com/Velocidex/velociraptor
- Community Forum: https://github.com/Velocidex/velociraptor/discussions

### PowerShell Group Policy

- Group Policy Cmdlets: https://docs.microsoft.com/en-us/powershell/module/grouppolicy/
- GPO Best Practices: https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/

## Version History

- **v1.0** - Initial release
  - GPO creation and configuration
  - Velociraptor deployment automation
  - Network share evidence collection
  - Windows Forms GUI

## License

This tool is provided as-is for use in authorized security and forensic operations.

## Disclaimer

This tool is designed for authorized digital forensics and incident response operations. Users are responsible for:

- Obtaining proper authorization before deployment
- Compliance with applicable laws and regulations
- Proper handling and storage of collected evidence
- Maintaining security of forensic data
- Following organizational policies and procedures

Use this tool only in authorized environments with proper legal authority.

## Contributing

Contributions and improvements are welcome. Please ensure:

- Code follows PowerShell best practices
- Changes are tested in lab environment
- Documentation is updated
- Security implications are considered

## Author

V-Rex: Velociraptor GPO Deployment Tool
Created for authorized forensic and incident response operations.
