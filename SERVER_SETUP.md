# Velociraptor Server Setup Guide

This guide covers installing and configuring a Velociraptor server that works with the V-Rex GPO deployment tool.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Server Installation](#server-installation)
- [Server Configuration](#server-configuration)
- [Creating Client Packages](#creating-client-packages)
- [Server Management](#server-management)
- [Integration with GPO Deployment](#integration-with-gpo-deployment)

---

## Prerequisites

### System Requirements

- **Operating System**: Windows Server 2012 R2 or later
- **RAM**: Minimum 4GB, recommended 8GB+ for production
- **Disk Space**: 50GB+ for datastore (scales with deployment size)
- **Network**: Static IP address or DNS name
- **Ports**:
  - 8000 (Frontend - client connections)
  - 8889 (GUI - web interface)
  - 8001 (API - optional)

### Software Requirements

- PowerShell 5.1 or later
- Administrative privileges
- .NET Framework 4.5+

### Velociraptor Download

Download the latest Velociraptor server executable:

1. Visit: https://github.com/Velocidex/velociraptor/releases
2. Download: `velociraptor-vX.X.X-windows-amd64.exe`
3. Save to a known location (e.g., `C:\Downloads`)

---

## Server Installation

### Method 1: GUI Installation (Recommended)

#### Step 1: Launch Installation Tool

```powershell
# Open PowerShell as Administrator
cd C:\Path\To\v-rex

# Run the installation script
.\Install-VelociraptorServer.ps1
```

#### Step 2: Configure Installation Settings

Fill in the GUI form:

| Field | Example | Description |
|-------|---------|-------------|
| **Installation Path** | `C:\Program Files\Velociraptor Server` | Where server will be installed |
| **Velociraptor EXE** | `C:\Downloads\velociraptor-v0.6.8-windows-amd64.exe` | Path to downloaded executable |
| **Hostname/IP** | `velociraptor.domain.local` or `192.168.1.100` | Server's DNS name or IP |
| **Frontend Port** | `8000` | Port for client connections (default: 8000) |
| **GUI Port** | `8889` | Port for web interface (default: 8889) |
| **Datastore Path** | `C:\VelociraptorData` | Where to store collected data |
| **Admin Username** | `admin` | Initial administrator username |
| **Admin Password** | `YourSecurePassword123!` | Initial admin password |
| **Auto-generate config** | ☑ Checked | Use Velociraptor's wizard (recommended) |

#### Step 3: Start Installation

1. Click **Install**
2. If auto-generate is enabled, an interactive wizard will appear
3. Answer the wizard prompts:
   - Hostname: Enter your server's hostname
   - Frontend port: 8000 (default)
   - GUI port: 8889 (default)
   - Datastore: Will use configured path
   - Self-signed SSL: Yes (for most deployments)

4. Wait for installation to complete
5. Check the log output for success messages

#### Step 4: Verify Installation

After installation completes:

```powershell
# Check service status
Get-Service -Name "VelociraptorServer"

# Should show: Status: Running

# Verify ports are listening
netstat -ano | findstr ":8000"
netstat -ano | findstr ":8889"

# Test GUI access
Start-Process "https://localhost:8889"
```

### Method 2: Manual Installation

If you prefer manual installation or the GUI fails:

```powershell
# 1. Create directories
New-Item -Path "C:\Program Files\Velociraptor Server" -ItemType Directory -Force
New-Item -Path "C:\VelociraptorData" -ItemType Directory -Force

# 2. Copy executable
Copy-Item "C:\Downloads\velociraptor-v0.6.8-windows-amd64.exe" `
    -Destination "C:\Program Files\Velociraptor Server\velociraptor.exe"

# 3. Generate configuration
cd "C:\Program Files\Velociraptor Server"
.\velociraptor.exe config generate -i

# Follow the interactive prompts

# 4. Install as service
.\velociraptor.exe --config server.config.yaml service install

# 5. Configure service
sc.exe config VelociraptorServer start= auto

# 6. Start service
Start-Service VelociraptorServer

# 7. Create admin user
.\velociraptor.exe --config server.config.yaml user add admin --role administrator
```

---

## Server Configuration

### Accessing the Web GUI

1. Open a web browser
2. Navigate to: `https://your-server:8889`
3. Accept the self-signed certificate warning (if using self-signed SSL)
4. Log in with admin credentials

### Initial Configuration Tasks

#### 1. Change Default Password

```powershell
cd "C:\Program Files\Velociraptor Server"
.\velociraptor.exe --config server.config.yaml user add admin --role administrator --password "NewSecurePassword"
```

#### 2. Configure Firewall Rules

The installation script should have created these rules automatically, but verify:

```powershell
# Check firewall rules
Get-NetFirewallRule -DisplayName "Velociraptor*" | Format-Table

# If not present, create them
New-NetFirewallRule -DisplayName "Velociraptor Frontend" `
    -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow

New-NetFirewallRule -DisplayName "Velociraptor GUI" `
    -Direction Inbound -Protocol TCP -LocalPort 8889 -Action Allow
```

#### 3. Configure SSL Certificate (Production)

For production, replace self-signed certificate:

1. Obtain proper SSL certificate
2. Edit `server.config.yaml`:

```yaml
Frontend:
  hostname: velociraptor.domain.local
  certificate: C:\Certificates\server.crt
  private_key: C:\Certificates\server.key
  use_self_signed_ssl: false
```

3. Restart service:
```powershell
Restart-Service VelociraptorServer
```

#### 4. Configure User Roles

Available roles:
- **administrator**: Full access
- **investigator**: Can run hunts and collect artifacts
- **analyst**: Can view results and create notebooks
- **reader**: Read-only access

Add users via GUI or command line:

```powershell
# Add investigator
.\velociraptor.exe --config server.config.yaml user add investigator1 --role investigator

# Add analyst
.\velociraptor.exe --config server.config.yaml user add analyst1 --role analyst
```

---

## Creating Client Packages

Before deploying via GPO, you need to create client installation packages.

### Method 1: Using Management GUI

1. Run `Manage-VelociraptorServer.ps1`
2. Go to "Client Package Generation" section
3. Select output directory
4. Click "Create Client MSI"

### Method 2: Command Line

```powershell
cd "C:\Program Files\Velociraptor Server"

# Create MSI installer
.\velociraptor.exe --config server.config.yaml config repack `
    --exe velociraptor.exe `
    --msi C:\Packages\velociraptor-client.msi

# Create client configuration
.\velociraptor.exe --config server.config.yaml config client > C:\Packages\client.config.yaml
```

The generated MSI includes:
- Velociraptor client executable
- Server configuration
- SSL certificates
- Service installer

---

## Server Management

### Using the Management GUI

```powershell
# Launch management console
.\Manage-VelociraptorServer.ps1
```

Features:
- **Service Control**: Start, stop, restart server
- **User Management**: Add users with different roles
- **Client Package Creation**: Generate MSI installers
- **Status Monitoring**: View service status and ports

### Common Management Tasks

#### View Connected Clients

Via GUI:
1. Open web interface: `https://your-server:8889`
2. Navigate to "Show All" under clients
3. View list of connected clients

Via Command Line:
```powershell
.\velociraptor.exe --config server.config.yaml query `
    "SELECT * FROM clients()"
```

#### Create a Hunt

Hunts collect artifacts from multiple clients:

1. In web GUI, go to "Hunts"
2. Click "New Hunt"
3. Select artifacts to collect (e.g., Windows.KapeFiles.Targets)
4. Set target clients (all or specific labels)
5. Launch hunt

#### View Logs

```powershell
# Service logs
Get-EventLog -LogName Application -Source "VelociraptorServer" -Newest 50

# Velociraptor logs
Get-ChildItem "C:\Program Files\Velociraptor Server\Logs" | Sort-Object LastWriteTime -Descending
Get-Content "C:\Program Files\Velociraptor Server\Logs\Frontend.log" -Tail 100
```

#### Backup Server

Important data to backup:
- Configuration: `server.config.yaml`
- Datastore: Entire datastore directory
- Certificates: If using custom SSL certificates

```powershell
# Backup script
$backupPath = "D:\Backups\Velociraptor\$(Get-Date -Format 'yyyy-MM-dd')"
New-Item -Path $backupPath -ItemType Directory -Force

# Copy configuration
Copy-Item "C:\Program Files\Velociraptor Server\server.config.yaml" $backupPath

# Backup datastore (use robocopy for large datasets)
robocopy "C:\VelociraptorData" "$backupPath\Datastore" /MIR /R:2 /W:5
```

---

## Integration with GPO Deployment

Once your server is installed and configured, integrate with the GPO deployment tool:

### Step 1: Locate Client MSI

After creating client package:
- MSI location: `C:\Packages\velociraptor-client.msi` (or your chosen path)

### Step 2: Copy MSI to Network Share

```powershell
# Create share if needed
New-SmbShare -Name "Software" -Path "C:\Software" -FullAccess "Administrators"

# Copy MSI
Copy-Item "C:\Packages\velociraptor-client.msi" "\\server\Software\"
```

### Step 3: Run GPO Deployment Tool

```powershell
.\Deploy-VelociraptorGPO.ps1
```

Configure with:
- **Velociraptor MSI**: `\\server\Software\velociraptor-client.msi`
- **Server URL**: `https://velociraptor.domain.local:8000`
- **Network Share**: `\\server\VelociraptorEvidence`

### Step 4: Monitor Client Connections

After GPO deployment:

1. Check web GUI for new client connections
2. Verify clients appear in client list
3. Check network share for evidence directories

```powershell
# Count connected clients
.\velociraptor.exe --config server.config.yaml query `
    "SELECT count(*) as client_count FROM clients()"

# Check recent connections
.\velociraptor.exe --config server.config.yaml query `
    "SELECT client_id, os_info.hostname, last_seen_at
     FROM clients()
     ORDER BY last_seen_at DESC
     LIMIT 10"
```

---

## Troubleshooting

### Server Won't Start

1. **Check service status**:
   ```powershell
   Get-Service VelociraptorServer
   Get-EventLog -LogName Application -Source "VelociraptorServer" -Newest 10
   ```

2. **Verify configuration**:
   ```powershell
   # Test configuration syntax
   cd "C:\Program Files\Velociraptor Server"
   .\velociraptor.exe --config server.config.yaml config show
   ```

3. **Check port conflicts**:
   ```powershell
   netstat -ano | findstr ":8000"
   netstat -ano | findstr ":8889"
   # If ports are in use by other processes, change ports in config
   ```

### Cannot Access Web GUI

1. **Verify service is running**:
   ```powershell
   Get-Service VelociraptorServer
   ```

2. **Check firewall**:
   ```powershell
   Test-NetConnection -ComputerName localhost -Port 8889
   Get-NetFirewallRule -DisplayName "Velociraptor GUI"
   ```

3. **Try different browser** or clear browser cache

4. **Check logs**:
   ```powershell
   Get-Content "C:\Program Files\Velociraptor Server\Logs\Frontend.log" -Tail 50
   ```

### Clients Not Connecting

1. **Verify server is accessible**:
   ```powershell
   # From client machine
   Test-NetConnection -ComputerName velociraptor.domain.local -Port 8000
   ```

2. **Check client configuration**:
   - Verify server URL in client config
   - Ensure SSL certificates match

3. **Check server logs**:
   ```powershell
   Get-Content "C:\Program Files\Velociraptor Server\Logs\Frontend.log" |
       Select-String "error"
   ```

### High Resource Usage

1. **Limit client connections**:
   Edit `server.config.yaml`:
   ```yaml
   Frontend:
     expected_clients: 1000  # Adjust based on your needs
   ```

2. **Configure resource limits**:
   ```yaml
   Resources:
     max_upload_size: 104857600  # 100MB
     max_memory: 4294967296      # 4GB
   ```

3. **Archive old data**:
   ```powershell
   # Move old hunts to archive
   # Implement data retention policy
   ```

---

## Performance Tuning

### For Large Deployments (1000+ clients)

1. **Increase server resources**:
   - 16GB+ RAM
   - SSD storage for datastore
   - Multiple CPU cores

2. **Optimize configuration**:
   ```yaml
   Frontend:
     expected_clients: 10000
     resources:
       connections_per_second: 100
       notifications_per_second: 100

   Datastore:
     # Use filestore with proper disk I/O
     implementation: FileBaseDataStore
   ```

3. **Database optimization**:
   - Regular datastore cleanup
   - Archive old hunts
   - Implement data retention

4. **Network optimization**:
   - Dedicated network interface
   - Quality of Service (QoS) rules
   - Load balancing (for very large deployments)

---

## Security Best Practices

1. **Change default passwords immediately**
2. **Use strong SSL certificates** (not self-signed) for production
3. **Implement role-based access control** (RBAC)
4. **Enable audit logging**
5. **Regular backups** of configuration and datastore
6. **Restrict network access** to server (firewall rules)
7. **Keep Velociraptor updated** to latest version
8. **Monitor server logs** for suspicious activity
9. **Separate networks** (management vs. client networks)
10. **Encrypt datastore** at rest

---

## Next Steps

After server setup:

1. ✅ Test server accessibility
2. ✅ Create client MSI package
3. ✅ Deploy to test group via GPO
4. ✅ Verify client connections
5. ✅ Configure artifact collection
6. ✅ Set up hunts for baseline data
7. ✅ Train IR team on Velociraptor usage
8. ✅ Implement monitoring and alerting
9. ✅ Document procedures
10. ✅ Expand deployment

---

## Additional Resources

- **Official Documentation**: https://docs.velociraptor.app/
- **GitHub Repository**: https://github.com/Velocidex/velociraptor
- **Community Discussions**: https://github.com/Velocidex/velociraptor/discussions
- **Artifact Exchange**: https://docs.velociraptor.app/exchange/

---

For GPO deployment, see [QUICKSTART.md](QUICKSTART.md) and [README.md](README.md).

For server management, run `Manage-VelociraptorServer.ps1`.
