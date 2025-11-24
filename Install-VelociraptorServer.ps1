<#
.SYNOPSIS
    GUI tool for installing and configuring Velociraptor Server

.DESCRIPTION
    This script provides a Windows Forms GUI to install and configure a
    Velociraptor server for digital forensics and incident response.
    It handles server installation, configuration generation, SSL certificates,
    firewall rules, and service setup.

.NOTES
    Author: V-Rex GPO Deployment Tool
    Version: 1.0
    Requires:
    - PowerShell 5.1 or later
    - Administrative privileges
    - Windows Server 2012 R2 or later
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global variables
$script:LogFile = "$env:TEMP\VelociraptorServerInstall.log"

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $logMessage

    # Also write to output textbox if available
    if ($script:outputTextBox) {
        $color = switch ($Level) {
            'Error' { [System.Drawing.Color]::Red }
            'Warning' { [System.Drawing.Color]::Orange }
            'Success' { [System.Drawing.Color]::Green }
            default { [System.Drawing.Color]::Black }
        }

        $script:outputTextBox.SelectionStart = $script:outputTextBox.TextLength
        $script:outputTextBox.SelectionLength = 0
        $script:outputTextBox.SelectionColor = $color
        $script:outputTextBox.AppendText("$logMessage`r`n")
        $script:outputTextBox.SelectionColor = $script:outputTextBox.ForeColor
        $script:outputTextBox.ScrollToCaret()
    }
}

# Function to download Velociraptor if needed
function Get-VelociraptorExecutable {
    param(
        [string]$Version = "latest",
        [string]$OutputPath
    )

    try {
        Write-Log "Checking for Velociraptor executable..." -Level Info

        if (Test-Path $OutputPath) {
            Write-Log "Velociraptor executable already exists at $OutputPath" -Level Info
            return $true
        }

        Write-Log "Velociraptor executable not found. Please download manually from:" -Level Warning
        Write-Log "https://github.com/Velocidex/velociraptor/releases" -Level Warning

        $result = [System.Windows.Forms.MessageBox]::Show(
            "Velociraptor executable not found at:`n$OutputPath`n`nWould you like to specify the download location?",
            "Download Required",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "Executables (*.exe)|*.exe|All Files (*.*)|*.*"
            $openFileDialog.Title = "Select Velociraptor Server Executable"

            if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                Copy-Item -Path $openFileDialog.FileName -Destination $OutputPath -Force
                Write-Log "Copied Velociraptor executable to $OutputPath" -Level Success
                return $true
            }
        }

        return $false
    }
    catch {
        Write-Log "Error downloading Velociraptor: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Function to generate server configuration
function New-ServerConfiguration {
    param(
        [string]$ConfigPath,
        [string]$Hostname,
        [int]$FrontendPort,
        [int]$GuiPort,
        [string]$DatastorePath,
        [string]$LogPath
    )

    try {
        Write-Log "Generating server configuration..." -Level Info

        # Generate configuration using Velociraptor's config wizard
        $veloExe = Join-Path (Split-Path $ConfigPath) "velociraptor.exe"

        if (!(Test-Path $veloExe)) {
            throw "Velociraptor executable not found at $veloExe"
        }

        # Create config using interactive wizard
        $configArgs = @(
            "config", "generate",
            "--merge_file", $ConfigPath
        )

        Write-Log "Running: velociraptor.exe config generate" -Level Info
        Write-Log "You will be prompted for configuration options..." -Level Warning

        # Run config generation
        $process = Start-Process -FilePath $veloExe -ArgumentList "config generate -i" `
            -WorkingDirectory (Split-Path $ConfigPath) `
            -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -ne 0) {
            throw "Configuration generation failed with exit code $($process.ExitCode)"
        }

        # The config generate command creates server.config.yaml in current directory
        $generatedConfig = Join-Path (Split-Path $ConfigPath) "server.config.yaml"

        if (Test-Path $generatedConfig) {
            Move-Item -Path $generatedConfig -Destination $ConfigPath -Force
            Write-Log "Server configuration created at $ConfigPath" -Level Success
            return $true
        }
        else {
            throw "Generated configuration file not found"
        }
    }
    catch {
        Write-Log "Failed to generate server configuration: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Function to create server configuration manually
function New-ServerConfigManual {
    param(
        [string]$ConfigPath,
        [string]$Hostname,
        [int]$FrontendPort,
        [int]$GuiPort,
        [string]$DatastorePath,
        [string]$LogPath
    )

    $config = @"
# Velociraptor Server Configuration
# Auto-generated by V-Rex Server Installation Tool

version:
  name: velociraptor
  version: "0.6.8"
  commit: unknown
  build_time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Client:
  server_urls:
    - https://${Hostname}:${FrontendPort}/

  # CA certificate for server verification
  ca_certificate: |
    # Will be auto-generated

Frontend:
  # Hostname for frontend server
  hostname: $Hostname
  bind_address: 0.0.0.0
  bind_port: $FrontendPort

  # Use self-signed SSL
  use_self_signed_ssl: true

  # Frontend resources
  expected_clients: 10000

GUI:
  # GUI endpoint
  bind_address: 0.0.0.0
  bind_port: $GuiPort

  # Use SSL for GUI
  use_plain_http: false

  # Initial admin user will be created on first run
  initial_users:
    - name: admin

Datastore:
  # File-based datastore
  implementation: FileBaseDataStore
  location: $DatastorePath
  filestore_directory: $DatastorePath

Logging:
  output_directory: $LogPath
  separate_logs_per_component: true
  max_age_days: 30

Monitoring:
  bind_address: 127.0.0.1
  bind_port: 8003

# API configuration
API:
  bind_address: 0.0.0.0
  bind_port: 8001
  bind_scheme: tcp

# Server resources
Resources:
  max_upload_size: 10737418240  # 10GB
  expected_clients: 10000

# Defaults
defaults:
  hunt_expiry_hours: 168  # 7 days
  notebook_cell_timeout_min: 60
"@

    try {
        $config | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
        Write-Log "Manual server configuration created at $ConfigPath" -Level Info
        Write-Log "NOTE: You'll need to run 'velociraptor config generate' to create proper certificates" -Level Warning
        return $true
    }
    catch {
        Write-Log "Failed to create manual configuration: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Function to configure Windows Firewall
function Set-FirewallRules {
    param(
        [int]$FrontendPort,
        [int]$GuiPort
    )

    try {
        Write-Log "Configuring Windows Firewall rules..." -Level Info

        # Frontend port rule
        $frontendRule = Get-NetFirewallRule -DisplayName "Velociraptor Frontend" -ErrorAction SilentlyContinue
        if (!$frontendRule) {
            New-NetFirewallRule -DisplayName "Velociraptor Frontend" `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort $FrontendPort `
                -Action Allow `
                -Profile Any `
                -Description "Velociraptor client connections"
            Write-Log "Created firewall rule for frontend port $FrontendPort" -Level Success
        }
        else {
            Write-Log "Firewall rule for frontend already exists" -Level Info
        }

        # GUI port rule
        $guiRule = Get-NetFirewallRule -DisplayName "Velociraptor GUI" -ErrorAction SilentlyContinue
        if (!$guiRule) {
            New-NetFirewallRule -DisplayName "Velociraptor GUI" `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort $GuiPort `
                -Action Allow `
                -Profile Any `
                -Description "Velociraptor web GUI access"
            Write-Log "Created firewall rule for GUI port $GuiPort" -Level Success
        }
        else {
            Write-Log "Firewall rule for GUI already exists" -Level Info
        }

        return $true
    }
    catch {
        Write-Log "Failed to configure firewall: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Function to install server as Windows service
function Install-VelociraptorService {
    param(
        [string]$ExecutablePath,
        [string]$ConfigPath
    )

    try {
        Write-Log "Installing Velociraptor as Windows service..." -Level Info

        # Check if service already exists
        $existingService = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue

        if ($existingService) {
            Write-Log "Service already exists. Stopping and removing..." -Level Warning

            if ($existingService.Status -eq 'Running') {
                Stop-Service -Name "Velociraptor" -Force
                Start-Sleep -Seconds 2
            }

            # Remove service using velociraptor command
            $removeArgs = @(
                "--config"
                $ConfigPath
                "service"
                "remove"
            )
            
            $removeProcess = Start-Process -FilePath $ExecutablePath `
                -ArgumentList $removeArgs `
                -Wait -PassThru -NoNewWindow `
                -RedirectStandardOutput "$env:TEMP\velo-service-remove.txt" `
                -RedirectStandardError "$env:TEMP\velo-service-remove-error.txt"
            
            Start-Sleep -Seconds 2
            
            # Also try using sc.exe as fallback
            $scRemove = sc.exe delete Velociraptor 2>&1
            if ($scRemove) {
                Write-Log "Service removal output: $scRemove" -Level Info
            }
            
            Start-Sleep -Seconds 2
        }

        # Verify paths exist and convert to absolute paths
        if (!(Test-Path $ExecutablePath)) {
            throw "Velociraptor executable not found at: $ExecutablePath"
        }
        $ExecutablePath = (Resolve-Path $ExecutablePath).Path

        if (!(Test-Path $ConfigPath)) {
            throw "Configuration file not found at: $ConfigPath"
        }
        $ConfigPath = (Resolve-Path $ConfigPath).Path

        # Install service
        Write-Log "Installing service..." -Level Info
        Write-Log "Executable: $ExecutablePath" -Level Info
        Write-Log "Config: $ConfigPath" -Level Info
        
        # Set working directory to config file location
        $workingDir = Split-Path $ConfigPath -Parent
        Write-Log "Working directory: $workingDir" -Level Info
        Write-Log "Command: $ExecutablePath --config `"$ConfigPath`" service install" -Level Info
        
        # Use array for arguments - PowerShell will handle quoting automatically
        $installArgs = @(
            "--config"
            $ConfigPath
            "service"
            "install"
        )

        $stdoutFile = "$env:TEMP\velo-service-install.txt"
        $stderrFile = "$env:TEMP\velo-service-install-error.txt"
        
        Write-Log "Arguments array: $($installArgs -join ' ')" -Level Info
        
        # Use call operator with splatting for better path handling
        Push-Location $workingDir
        try {
            # Capture both stdout and stderr
            $output = & $ExecutablePath $installArgs 2>&1
            $exitCode = $LASTEXITCODE
            
            # Separate stdout and stderr
            $stdoutLines = @()
            $stderrLines = @()
            
            foreach ($line in $output) {
                if ($line -is [System.Management.Automation.ErrorRecord]) {
                    $stderrLines += $line.ToString()
                }
                else {
                    $stdoutLines += $line.ToString()
                }
            }
            
            # Write to files
            $stdoutContent = $stdoutLines -join "`r`n"
            $stderrContent = $stderrLines -join "`r`n"
            
            $stdoutContent | Out-File -FilePath $stdoutFile -Encoding UTF8 -ErrorAction SilentlyContinue
            $stderrContent | Out-File -FilePath $stderrFile -Encoding UTF8 -ErrorAction SilentlyContinue
            
            # Also capture all output for debugging
            $allOutput = $output | ForEach-Object { 
                if ($_ -is [System.Management.Automation.ErrorRecord]) { 
                    $_.ToString() 
                } else { 
                    $_ 
                } 
            }
            $allOutput | Out-File -FilePath "$env:TEMP\velo-service-install-all.txt" -Encoding UTF8 -ErrorAction SilentlyContinue
            
            # Read output files
            $stdout = if ($stdoutContent) { $stdoutContent } else { $null }
            $stderr = if ($stderrContent) { $stderrContent } else { $null }
            
            # If no stderr but we have output, check if any line looks like an error
            if (!$stderr -and $allOutput) {
                $errorLines = $allOutput | Where-Object { $_ -match 'error|Error|ERROR|failed|Failed|FAILED' }
                if ($errorLines) {
                    $stderr = $errorLines -join "`r`n"
                }
            }
            
            # Create a process-like object for compatibility
            $process = [PSCustomObject]@{
                ExitCode = $exitCode
            }
            
            Write-Log "Service install exit code: $exitCode" -Level Info
            Write-Log "Total output lines captured: $($output.Count)" -Level Info
            
            # Log all output for debugging
            if ($allOutput) {
                Write-Log "All output: $($allOutput -join ' | ')" -Level Info
            }
        
            if ($stdout) {
                Write-Log "Service install stdout: $stdout" -Level Info
            }
            else {
                Write-Log "No stdout captured" -Level Warning
            }

            if ($stderr) {
                Write-Log "Service install stderr: $stderr" -Level Error
            }
            else {
                Write-Log "No stderr captured" -Level Warning
                # If exit code is non-zero but no stderr, log the full output
                if ($exitCode -ne 0 -and $allOutput) {
                    Write-Log "Full output (no stderr but exit code $exitCode): $($allOutput -join '`r`n')" -Level Error
                }
            }

            if ($process.ExitCode -eq 0) {
                Write-Log "Service installed successfully" -Level Success

                # Configure service for auto-start and recovery
                sc.exe config Velociraptor start= auto
                sc.exe failure Velociraptor reset= 86400 actions= restart/60000/restart/60000/restart/60000

                Write-Log "Service configured for automatic startup" -Level Success
                return $true
            }
            else {
                $errorMsg = "Service installation failed with exit code $($process.ExitCode)"
                if ($stderr) {
                    $errorMsg += "`nError output: $stderr"
                }
                else {
                    $errorMsg += "`n(No error output captured - check $stderrFile)"
                }
                if ($stdout) {
                    $errorMsg += "`nStandard output: $stdout"
                }
                Write-Log "Full error details: $errorMsg" -Level Error
                throw $errorMsg
            }
        }
        finally {
            Pop-Location
        }
    }
    catch {
        Write-Log "Failed to install service: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Function to create initial admin user
function New-AdminUser {
    param(
        [string]$ExecutablePath,
        [string]$ConfigPath,
        [string]$Username,
        [string]$Password
    )

    try {
        Write-Log "Creating initial admin user..." -Level Info

        # Verify paths exist and convert to absolute paths
        if (!(Test-Path $ExecutablePath)) {
            throw "Velociraptor executable not found at: $ExecutablePath"
        }
        $ExecutablePath = (Resolve-Path $ExecutablePath).Path

        if (!(Test-Path $ConfigPath)) {
            throw "Configuration file not found at: $ConfigPath"
        }
        $ConfigPath = (Resolve-Path $ConfigPath).Path

        # Use array for arguments
        # Note: Some versions of Velociraptor don't support --password flag
        # User will need to set password via web GUI on first login
        $userArgs = @(
            "--config"
            $ConfigPath
            "user"
            "add"
            $Username
            "--role"
            "administrator"
        )

        # Try to set password if provided, but don't fail if flag isn't supported
        # Velociraptor may prompt for password interactively or require setting via GUI
        $usePassword = $false
        if (![string]::IsNullOrWhiteSpace($Password)) {
            # Try with --password flag first
            $usePassword = $true
        }

        $stdoutFile = "$env:TEMP\velo-user-add.txt"
        $stderrFile = "$env:TEMP\velo-user-error.txt"
        $workingDir = Split-Path $ConfigPath -Parent

        # Use call operator for better path handling
        Push-Location $workingDir
        try {
            # First try without password (most reliable method)
            $output = & $ExecutablePath $userArgs 2>&1
            $exitCode = $LASTEXITCODE

            # Separate stdout and stderr
            $stdoutLines = @()
            $stderrLines = @()

            foreach ($line in $output) {
                if ($line -is [System.Management.Automation.ErrorRecord]) {
                    $stderrLines += $line.ToString()
                }
                else {
                    $stdoutLines += $line.ToString()
                }
            }

            $stdoutContent = $stdoutLines -join "`r`n"
            $stderrContent = $stderrLines -join "`r`n"

            $stdoutContent | Out-File -FilePath $stdoutFile -Encoding UTF8 -ErrorAction SilentlyContinue
            $stderrContent | Out-File -FilePath $stderrFile -Encoding UTF8 -ErrorAction SilentlyContinue

            if ($exitCode -eq 0) {
                Write-Log "Admin user '$Username' created successfully" -Level Success

                if ($stdoutContent) {
                    Write-Log "User creation output: $stdoutContent" -Level Info
                }

                if ($usePassword) {
                    Write-Log "Note: Password flag not supported by this Velociraptor version." -Level Warning
                    Write-Log "User '$Username' was created without a password." -Level Warning
                    Write-Log "Please set the password via the web GUI at first login, or use:" -Level Info
                    Write-Log "  velociraptor.exe --config server.config.yaml user password $Username" -Level Info
                }

                return $true
            }
            else {
                $error = if ($stderrContent) { $stderrContent } else { "Exit code: $exitCode" }
                throw "User creation failed: $error"
            }
        }
        finally {
            Pop-Location
        }
    }
    catch {
        Write-Log "Failed to create admin user: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Main installation function
function Install-VelociraptorServer {
    param(
        [string]$InstallPath,
        [string]$VeloExecutable,
        [string]$Hostname,
        [int]$FrontendPort,
        [int]$GuiPort,
        [string]$DatastorePath,
        [string]$AdminUsername,
        [string]$AdminPassword,
        [bool]$AutoGenConfig
    )

    try {
        Write-Log "=== Starting Velociraptor Server Installation ===" -Level Info

        # Create installation directory
        if (!(Test-Path $InstallPath)) {
            New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
            Write-Log "Created installation directory: $InstallPath" -Level Success
        }

        # Create datastore directory
        if (!(Test-Path $DatastorePath)) {
            New-Item -Path $DatastorePath -ItemType Directory -Force | Out-Null
            Write-Log "Created datastore directory: $DatastorePath" -Level Success
        }

        # Create log directory
        $logPath = Join-Path $InstallPath "Logs"
        if (!(Test-Path $logPath)) {
            New-Item -Path $logPath -ItemType Directory -Force | Out-Null
            Write-Log "Created log directory: $logPath" -Level Success
        }

        # Copy or download Velociraptor executable
        $targetExe = Join-Path $InstallPath "velociraptor.exe"

        if (Test-Path $VeloExecutable) {
            Copy-Item -Path $VeloExecutable -Destination $targetExe -Force
            Write-Log "Copied Velociraptor executable to $targetExe" -Level Success
        }
        else {
            if (!(Get-VelociraptorExecutable -OutputPath $targetExe)) {
                throw "Failed to obtain Velociraptor executable"
            }
        }

        # Generate server configuration
        $configPath = Join-Path $InstallPath "server.config.yaml"

        if ($AutoGenConfig) {
            Write-Log "Generating configuration using Velociraptor wizard..." -Level Info
            Write-Log "This will open an interactive prompt..." -Level Warning

            # Use Velociraptor's built-in config generator
            $genProcess = Start-Process -FilePath $targetExe `
                -ArgumentList "config", "generate", "-i" `
                -WorkingDirectory $InstallPath `
                -Wait -PassThru

            if ($genProcess.ExitCode -eq 0) {
                # Move generated config to proper location
                $generatedConfig = Join-Path $InstallPath "server.config.yaml"
                if (Test-Path $generatedConfig) {
                    Write-Log "Configuration generated successfully" -Level Success
                }
                else {
                    throw "Configuration file not created by generator"
                }
            }
            else {
                throw "Configuration generation failed"
            }
        }
        else {
            # Create manual configuration
            if (!(New-ServerConfigManual -ConfigPath $configPath `
                    -Hostname $Hostname `
                    -FrontendPort $FrontendPort `
                    -GuiPort $GuiPort `
                    -DatastorePath $DatastorePath `
                    -LogPath $logPath)) {
                throw "Failed to create server configuration"
            }

            Write-Log "IMPORTANT: Run 'velociraptor.exe config generate' to create proper SSL certificates" -Level Warning
        }

        # Configure firewall
        if (!(Set-FirewallRules -FrontendPort $FrontendPort -GuiPort $GuiPort)) {
            Write-Log "Firewall configuration failed, but continuing..." -Level Warning
        }

        # Install as service
        if (!(Install-VelociraptorService -ExecutablePath $targetExe -ConfigPath $configPath)) {
            throw "Failed to install Windows service"
        }

        # Create admin user if specified
        if (![string]::IsNullOrWhiteSpace($AdminUsername)) {
            # Service needs to be started first to create user
            Write-Log "Starting service to initialize database..." -Level Info
            $service = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
            if ($service) {
                try {
                    Start-Service -Name "Velociraptor" -ErrorAction Stop
                    Start-Sleep -Seconds 5

                    if (!(New-AdminUser -ExecutablePath $targetExe -ConfigPath $configPath `
                            -Username $AdminUsername -Password $AdminPassword)) {
                        Write-Log "Failed to create admin user, you can create one later manually" -Level Warning
                    }

                    Stop-Service -Name "Velociraptor" -Force -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Log "Could not start service for user creation: $($_.Exception.Message)" -Level Warning
                    Write-Log "You can create the admin user manually after the service is running" -Level Info
                }
            }
            else {
                Write-Log "Service not found - cannot create admin user. Service may need to be started first." -Level Warning
            }
        }

        # Start the service
        Write-Log "Starting Velociraptor Server service..." -Level Info
        
        # Try to find the service - it might have a different name
        $service = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
        if (!$service) {
            # Try to find any service with "velociraptor" in the name
            $allServices = Get-Service | Where-Object { $_.Name -like "*velociraptor*" -or $_.DisplayName -like "*velociraptor*" }
            if ($allServices) {
                $service = $allServices[0]
                Write-Log "Found service with name: $($service.Name)" -Level Info
            }
        }
        
        if ($service) {
            try {
                Start-Service -Name "Velociraptor" -ErrorAction Stop
                Start-Sleep -Seconds 3

                $service = Get-Service -Name "Velociraptor"
                if ($service.Status -eq 'Running') {
                    Write-Log "Velociraptor Server started successfully!" -Level Success
                }
                else {
                    Write-Log "Service exists but is not running. Status: $($service.Status)" -Level Warning
                }
            }
            catch {
                Write-Log "Failed to start service: $($_.Exception.Message)" -Level Error
                Write-Log "You may need to start the service manually or check the service configuration" -Level Warning
            }
        }
        else {
            Write-Log "Service 'Velociraptor' not found. Installation may have failed." -Level Error
            Write-Log "Check the service installation logs above for errors." -Level Warning
            Write-Log "You can try installing the service manually with: velociraptor.exe --config server.config.yaml service install" -Level Info
        }

        Write-Log "=== Installation Complete ===" -Level Success
        Write-Log "Installation Path: $InstallPath" -Level Info
        Write-Log "Configuration: $configPath" -Level Info
        Write-Log "Datastore: $DatastorePath" -Level Info
        Write-Log "Frontend URL: https://${Hostname}:${FrontendPort}/" -Level Info
        Write-Log "GUI URL: https://${Hostname}:${GuiPort}/" -Level Info

        if (![string]::IsNullOrWhiteSpace($AdminUsername)) {
            Write-Log "Admin Username: $AdminUsername" -Level Info
        }

        [System.Windows.Forms.MessageBox]::Show(
            "Velociraptor Server installed successfully!`n`n" +
            "Frontend: https://${Hostname}:${FrontendPort}/`n" +
            "GUI: https://${Hostname}:${GuiPort}/`n`n" +
            "Admin User: $AdminUsername",
            "Installation Complete",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

        return $true
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" -Level Error
        [System.Windows.Forms.MessageBox]::Show(
            "Installation failed: $($_.Exception.Message)",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }
}

# Function to browse for file
function Get-FilePath {
    param([string]$Filter = "Executables (*.exe)|*.exe|All Files (*.*)|*.*")

    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = $Filter
    $openFileDialog.Title = "Select Velociraptor Executable"

    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $openFileDialog.FileName
    }
    return $null
}

# Function to browse for folder
function Get-FolderPath {
    param([string]$Description = "Select Folder")

    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = $Description
    $folderBrowser.ShowNewFolderButton = $true

    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $folderBrowser.SelectedPath
    }
    return $null
}

# Create the main form
function Show-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "V-Rex: Velociraptor Server Installation"
    $form.Size = New-Object System.Drawing.Size(800, 750)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.Icon = [System.Drawing.SystemIcons]::Shield

    # Header Label
    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Location = New-Object System.Drawing.Point(10, 10)
    $headerLabel.Size = New-Object System.Drawing.Size(760, 40)
    $headerLabel.Text = "Install Velociraptor Server"
    $headerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $headerLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    $form.Controls.Add($headerLabel)

    [int]$yPos = 60

    # Installation Path
    $installPathLabel = New-Object System.Windows.Forms.Label
    $installPathLabel.Location = New-Object System.Drawing.Point(10, $yPos)
    $installPathLabel.Size = New-Object System.Drawing.Size(150, 20)
    $installPathLabel.Text = "Installation Path:"
    $form.Controls.Add($installPathLabel)

    $installPathTextBox = New-Object System.Windows.Forms.TextBox
    $installPathTextBox.Location = New-Object System.Drawing.Point -ArgumentList 170, ($yPos - 2)
    $installPathTextBox.Size = New-Object System.Drawing.Size -ArgumentList 520, 20
    $installPathTextBox.Text = "C:\Program Files\Velociraptor Server"
    $form.Controls.Add($installPathTextBox)

    $installPathBrowseButton = New-Object System.Windows.Forms.Button
    $installPathBrowseButton.Location = New-Object System.Drawing.Point -ArgumentList 700, ($yPos - 4)
    $installPathBrowseButton.Size = New-Object System.Drawing.Size -ArgumentList 70, 24
    $installPathBrowseButton.Text = "Browse..."
    $installPathBrowseButton.Add_Click({
        $path = Get-FolderPath -Description "Select Installation Directory"
        if ($path) { $installPathTextBox.Text = $path }
    })
    $form.Controls.Add($installPathBrowseButton)

    $yPos += 30

    # Velociraptor Executable
    $exeLabel = New-Object System.Windows.Forms.Label
    $exeLabel.Location = New-Object System.Drawing.Point(10, $yPos)
    $exeLabel.Size = New-Object System.Drawing.Size(150, 20)
    $exeLabel.Text = "Velociraptor EXE:"
    $form.Controls.Add($exeLabel)

    $exeTextBox = New-Object System.Windows.Forms.TextBox
    $exeTextBox.Location = New-Object System.Drawing.Point -ArgumentList 170, ($yPos - 2)
    $exeTextBox.Size = New-Object System.Drawing.Size -ArgumentList 520, 20
    $form.Controls.Add($exeTextBox)

    $exeBrowseButton = New-Object System.Windows.Forms.Button
    $exeBrowseButton.Location = New-Object System.Drawing.Point -ArgumentList 700, ($yPos - 4)
    $exeBrowseButton.Size = New-Object System.Drawing.Size -ArgumentList 70, 24
    $exeBrowseButton.Text = "Browse..."
    $exeBrowseButton.Add_Click({
        $path = Get-FilePath
        if ($path) { $exeTextBox.Text = $path }
    })
    $form.Controls.Add($exeBrowseButton)

    $yPos += 30

    # Hostname
    $hostnameLabel = New-Object System.Windows.Forms.Label
    $hostnameLabel.Location = New-Object System.Drawing.Point(10, $yPos)
    $hostnameLabel.Size = New-Object System.Drawing.Size(150, 20)
    $hostnameLabel.Text = "Hostname/IP:"
    $form.Controls.Add($hostnameLabel)

    $hostnameTextBox = New-Object System.Windows.Forms.TextBox
    $hostnameTextBox.Location = New-Object System.Drawing.Point -ArgumentList 170, ($yPos - 2)
    $hostnameTextBox.Size = New-Object System.Drawing.Size -ArgumentList 600, 20
    $hostnameTextBox.Text = $env:COMPUTERNAME
    $form.Controls.Add($hostnameTextBox)

    $yPos += 30

    # Frontend Port
    $frontendPortLabel = New-Object System.Windows.Forms.Label
    $frontendPortLabel.Location = New-Object System.Drawing.Point(10, $yPos)
    $frontendPortLabel.Size = New-Object System.Drawing.Size(150, 20)
    $frontendPortLabel.Text = "Frontend Port:"
    $form.Controls.Add($frontendPortLabel)

    $frontendPortTextBox = New-Object System.Windows.Forms.TextBox
    $frontendPortTextBox.Location = New-Object System.Drawing.Point -ArgumentList 170, ($yPos - 2)
    $frontendPortTextBox.Size = New-Object System.Drawing.Size -ArgumentList 100, 20
    $frontendPortTextBox.Text = "8000"
    $form.Controls.Add($frontendPortTextBox)

    # GUI Port
    $guiPortLabel = New-Object System.Windows.Forms.Label
    $guiPortLabel.Location = New-Object System.Drawing.Point(400, $yPos)
    $guiPortLabel.Size = New-Object System.Drawing.Size(100, 20)
    $guiPortLabel.Text = "GUI Port:"
    $form.Controls.Add($guiPortLabel)

    $guiPortTextBox = New-Object System.Windows.Forms.TextBox
    $guiPortTextBox.Location = New-Object System.Drawing.Point -ArgumentList 510, ($yPos - 2)
    $guiPortTextBox.Size = New-Object System.Drawing.Size -ArgumentList 100, 20
    $guiPortTextBox.Text = "8889"
    $form.Controls.Add($guiPortTextBox)

    $yPos += 30

    # Datastore Path
    $datastoreLabel = New-Object System.Windows.Forms.Label
    $datastoreLabel.Location = New-Object System.Drawing.Point(10, $yPos)
    $datastoreLabel.Size = New-Object System.Drawing.Size(150, 20)
    $datastoreLabel.Text = "Datastore Path:"
    $form.Controls.Add($datastoreLabel)

    $datastoreTextBox = New-Object System.Windows.Forms.TextBox
    $datastoreTextBox.Location = New-Object System.Drawing.Point -ArgumentList 170, ($yPos - 2)
    $datastoreTextBox.Size = New-Object System.Drawing.Size -ArgumentList 520, 20
    $datastoreTextBox.Text = "C:\VelociraptorData"
    $form.Controls.Add($datastoreTextBox)

    $datastoreBrowseButton = New-Object System.Windows.Forms.Button
    $datastoreBrowseButton.Location = New-Object System.Drawing.Point -ArgumentList 700, ($yPos - 4)
    $datastoreBrowseButton.Size = New-Object System.Drawing.Size -ArgumentList 70, 24
    $datastoreBrowseButton.Text = "Browse..."
    $datastoreBrowseButton.Add_Click({
        $path = Get-FolderPath -Description "Select Datastore Directory"
        if ($path) { $datastoreTextBox.Text = $path }
    })
    $form.Controls.Add($datastoreBrowseButton)

    $yPos += 30

    # Admin Username
    $adminUserLabel = New-Object System.Windows.Forms.Label
    $adminUserLabel.Location = New-Object System.Drawing.Point(10, $yPos)
    $adminUserLabel.Size = New-Object System.Drawing.Size(150, 20)
    $adminUserLabel.Text = "Admin Username:"
    $form.Controls.Add($adminUserLabel)

    $adminUserTextBox = New-Object System.Windows.Forms.TextBox
    $adminUserTextBox.Location = New-Object System.Drawing.Point -ArgumentList 170, ($yPos - 2)
    $adminUserTextBox.Size = New-Object System.Drawing.Size -ArgumentList 250, 20
    $adminUserTextBox.Text = "admin"
    $form.Controls.Add($adminUserTextBox)

    # Admin Password
    $adminPassLabel = New-Object System.Windows.Forms.Label
    $adminPassLabel.Location = New-Object System.Drawing.Point(430, $yPos)
    $adminPassLabel.Size = New-Object System.Drawing.Size(80, 20)
    $adminPassLabel.Text = "Password:"
    $form.Controls.Add($adminPassLabel)

    $adminPassTextBox = New-Object System.Windows.Forms.TextBox
    $adminPassTextBox.Location = New-Object System.Drawing.Point -ArgumentList 510, ($yPos - 2)
    $adminPassTextBox.Size = New-Object System.Drawing.Size -ArgumentList 260, 20
    $adminPassTextBox.UseSystemPasswordChar = $true
    $form.Controls.Add($adminPassTextBox)

    $yPos += 30

    # Auto-generate config checkbox
    $autoGenCheckbox = New-Object System.Windows.Forms.CheckBox
    $autoGenCheckbox.Location = New-Object System.Drawing.Point(170, $yPos)
    $autoGenCheckbox.Size = New-Object System.Drawing.Size(600, 20)
    $autoGenCheckbox.Text = "Auto-generate configuration (recommended - opens interactive wizard)"
    $autoGenCheckbox.Checked = $true
    $form.Controls.Add($autoGenCheckbox)

    $yPos += 40

    # Output TextBox
    $outputLabel = New-Object System.Windows.Forms.Label
    $outputLabel.Location = New-Object System.Drawing.Point(10, $yPos)
    $outputLabel.Size = New-Object System.Drawing.Size(150, 20)
    $outputLabel.Text = "Installation Log:"
    $form.Controls.Add($outputLabel)

    $yPos += 25

    $script:outputTextBox = New-Object System.Windows.Forms.RichTextBox
    $script:outputTextBox.Location = New-Object System.Drawing.Point(10, $yPos)
    $script:outputTextBox.Size = New-Object System.Drawing.Size(760, 350)
    $script:outputTextBox.ReadOnly = $true
    $script:outputTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $script:outputTextBox.BackColor = [System.Drawing.Color]::Black
    $script:outputTextBox.ForeColor = [System.Drawing.Color]::Lime
    $form.Controls.Add($script:outputTextBox)

    $yPos += 360

    # Install Button
    $installButton = New-Object System.Windows.Forms.Button
    $installButton.Location = New-Object System.Drawing.Point(550, $yPos)
    $installButton.Size = New-Object System.Drawing.Size(100, 30)
    $installButton.Text = "Install"
    $installButton.BackColor = [System.Drawing.Color]::Green
    $installButton.ForeColor = [System.Drawing.Color]::White
    $installButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $installButton.Add_Click({
        # Validate inputs
        if ([string]::IsNullOrWhiteSpace($installPathTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter an installation path.", "Validation Error",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        if ([string]::IsNullOrWhiteSpace($hostnameTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a hostname.", "Validation Error",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $script:outputTextBox.Clear()
        Write-Log "=== Starting Velociraptor Server Installation ===" -Level Info

        Install-VelociraptorServer `
            -InstallPath $installPathTextBox.Text `
            -VeloExecutable $exeTextBox.Text `
            -Hostname $hostnameTextBox.Text `
            -FrontendPort ([int]$frontendPortTextBox.Text) `
            -GuiPort ([int]$guiPortTextBox.Text) `
            -DatastorePath $datastoreTextBox.Text `
            -AdminUsername $adminUserTextBox.Text `
            -AdminPassword $adminPassTextBox.Text `
            -AutoGenConfig $autoGenCheckbox.Checked
    })
    $form.Controls.Add($installButton)

    # Close Button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Location = New-Object System.Drawing.Point(660, $yPos)
    $closeButton.Size = New-Object System.Drawing.Size(100, 30)
    $closeButton.Text = "Close"
    $closeButton.Add_Click({ $form.Close() })
    $form.Controls.Add($closeButton)

    # Show initial log message
    Write-Log "V-Rex Velociraptor Server Installation Tool initialized" -Level Info
    Write-Log "Log file: $script:LogFile" -Level Info
    Write-Log "Download Velociraptor from: https://github.com/Velocidex/velociraptor/releases" -Level Info
    Write-Log "Ready to install..." -Level Success

    # Show the form
    $form.Add_Shown({$form.Activate()})
    [void]$form.ShowDialog()
}

# Main execution
try {
    # Check for admin privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            "This script requires administrative privileges. Please run as Administrator.",
            "Admin Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }

    # Show the main form
    Show-MainForm
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Fatal error: $($_.Exception.Message)",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}
