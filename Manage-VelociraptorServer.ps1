<#
.SYNOPSIS
    GUI tool for managing Velociraptor Server

.DESCRIPTION
    This script provides a Windows Forms GUI to manage an installed
    Velociraptor server including service control, user management,
    and server configuration.

.NOTES
    Author: V-Rex GPO Deployment Tool
    Version: 1.0
    Requires: Administrative privileges
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global variables
$script:ConfigPath = "C:\Program Files\Velociraptor Server\server.config.yaml"
$script:ExePath = "C:\Program Files\Velociraptor Server\velociraptor.exe"

# Function to get service status
function Get-ServerStatus {
    try {
        $service = Get-Service -Name "VelociraptorServer" -ErrorAction SilentlyContinue
        if ($service) {
            return @{
                Exists = $true
                Status = $service.Status
                StartType = $service.StartType
            }
        }
        else {
            return @{
                Exists = $false
                Status = "Not Installed"
                StartType = "N/A"
            }
        }
    }
    catch {
        return @{
            Exists = $false
            Status = "Error"
            StartType = "N/A"
        }
    }
}

# Function to control service
function Set-ServerService {
    param(
        [ValidateSet('Start', 'Stop', 'Restart')]
        [string]$Action
    )

    try {
        switch ($Action) {
            'Start' {
                Start-Service -Name "VelociraptorServer"
                return "Server started successfully"
            }
            'Stop' {
                Stop-Service -Name "VelociraptorServer" -Force
                return "Server stopped successfully"
            }
            'Restart' {
                Restart-Service -Name "VelociraptorServer" -Force
                return "Server restarted successfully"
            }
        }
    }
    catch {
        return "Error: $($_.Exception.Message)"
    }
}

# Function to add user
function Add-ServerUser {
    param(
        [string]$Username,
        [string]$Password,
        [string]$Role
    )

    try {
        if (!(Test-Path $script:ExePath)) {
            throw "Velociraptor executable not found at $script:ExePath"
        }

        if (!(Test-Path $script:ConfigPath)) {
            throw "Configuration file not found at $script:ConfigPath"
        }

        $args = @(
            "--config", $script:ConfigPath,
            "user", "add",
            $Username,
            "--role", $Role
        )

        if (![string]::IsNullOrWhiteSpace($Password)) {
            $args += "--password"
            $args += $Password
        }

        $process = Start-Process -FilePath $script:ExePath `
            -ArgumentList $args `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput "$env:TEMP\velo-user-add.txt" `
            -RedirectStandardError "$env:TEMP\velo-user-error.txt"

        if ($process.ExitCode -eq 0) {
            $output = Get-Content "$env:TEMP\velo-user-add.txt" -Raw -ErrorAction SilentlyContinue
            return "User '$Username' created successfully.`n$output"
        }
        else {
            $error = Get-Content "$env:TEMP\velo-user-error.txt" -Raw -ErrorAction SilentlyContinue
            throw "User creation failed: $error"
        }
    }
    catch {
        return "Error: $($_.Exception.Message)"
    }
}

# Function to create client MSI
function New-ClientMSI {
    param(
        [string]$OutputPath
    )

    try {
        if (!(Test-Path $script:ExePath)) {
            throw "Velociraptor executable not found at $script:ExePath"
        }

        if (!(Test-Path $script:ConfigPath)) {
            throw "Configuration file not found at $script:ConfigPath"
        }

        $msiPath = Join-Path $OutputPath "velociraptor-client.msi"

        $args = @(
            "--config", $script:ConfigPath,
            "config", "repack",
            "--exe", $script:ExePath,
            "--msi", $msiPath
        )

        $process = Start-Process -FilePath $script:ExePath `
            -ArgumentList $args `
            -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            return "Client MSI created: $msiPath"
        }
        else {
            throw "MSI creation failed with exit code $($process.ExitCode)"
        }
    }
    catch {
        return "Error: $($_.Exception.Message)"
    }
}

# Function to get server info
function Get-ServerInfo {
    try {
        $info = @{}

        # Check if files exist
        $info.ExeExists = Test-Path $script:ExePath
        $info.ConfigExists = Test-Path $script:ConfigPath

        # Get service info
        $serviceStatus = Get-ServerStatus
        $info.ServiceStatus = $serviceStatus.Status
        $info.ServiceStartType = $serviceStatus.StartType

        # Read config file for details
        if ($info.ConfigExists) {
            $config = Get-Content $script:ConfigPath -Raw
            # Parse YAML for key information (basic regex parsing)
            if ($config -match "bind_port:\s*(\d+)") {
                $info.FrontendPort = $matches[1]
            }
            if ($config -match "GUI:[\s\S]*?bind_port:\s*(\d+)") {
                $info.GuiPort = $matches[1]
            }
            if ($config -match "hostname:\s*(.+)") {
                $info.Hostname = $matches[1].Trim()
            }
        }

        # Check listening ports
        $netstat = netstat -ano | Select-String "LISTENING"
        if ($info.FrontendPort -and $netstat -match ":$($info.FrontendPort)\s") {
            $info.FrontendListening = $true
        }
        if ($info.GuiPort -and $netstat -match ":$($info.GuiPort)\s") {
            $info.GuiListening = $true
        }

        return $info
    }
    catch {
        return @{ Error = $_.Exception.Message }
    }
}

# Create the main form
function Show-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "V-Rex: Velociraptor Server Management"
    $form.Size = New-Object System.Drawing.Size(700, 650)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.Icon = [System.Drawing.SystemIcons]::Application

    # Header Label
    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Location = New-Object System.Drawing.Point(10, 10)
    $headerLabel.Size = New-Object System.Drawing.Size(660, 30)
    $headerLabel.Text = "Velociraptor Server Management Console"
    $headerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $headerLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    $form.Controls.Add($headerLabel)

    # Server Status Group
    $statusGroup = New-Object System.Windows.Forms.GroupBox
    $statusGroup.Location = New-Object System.Drawing.Point(10, 50)
    $statusGroup.Size = New-Object System.Drawing.Size(660, 120)
    $statusGroup.Text = "Server Status"
    $form.Controls.Add($statusGroup)

    # Status display
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 25)
    $statusLabel.Size = New-Object System.Drawing.Size(640, 60)
    $statusLabel.Font = New-Object System.Drawing.Font("Consolas", 9)
    $statusLabel.Text = "Loading..."
    $statusGroup.Controls.Add($statusLabel)

    # Refresh button
    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Location = New-Object System.Drawing.Point(10, 85)
    $refreshButton.Size = New-Object System.Drawing.Size(80, 25)
    $refreshButton.Text = "Refresh"
    $refreshButton.Add_Click({
        $info = Get-ServerInfo
        $status = "Service Status: $($info.ServiceStatus)`n"
        $status += "Start Type: $($info.ServiceStartType)`n"
        if ($info.Hostname) { $status += "Hostname: $($info.Hostname)`n" }
        if ($info.FrontendPort) {
            $frontendStatus = if ($info.FrontendListening) { "Listening" } else { "Not Listening" }
            $status += "Frontend: Port $($info.FrontendPort) - $frontendStatus`n"
        }
        if ($info.GuiPort) {
            $guiStatus = if ($info.GuiListening) { "Listening" } else { "Not Listening" }
            $status += "GUI: Port $($info.GuiPort) - $guiStatus"
        }
        $statusLabel.Text = $status
    })
    $statusGroup.Controls.Add($refreshButton)

    # Service Control Group
    $serviceGroup = New-Object System.Windows.Forms.GroupBox
    $serviceGroup.Location = New-Object System.Drawing.Point(10, 180)
    $serviceGroup.Size = New-Object System.Drawing.Size(660, 80)
    $serviceGroup.Text = "Service Control"
    $form.Controls.Add($serviceGroup)

    # Start button
    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Location = New-Object System.Drawing.Point(10, 30)
    $startButton.Size = New-Object System.Drawing.Size(100, 30)
    $startButton.Text = "Start"
    $startButton.BackColor = [System.Drawing.Color]::Green
    $startButton.ForeColor = [System.Drawing.Color]::White
    $startButton.Add_Click({
        $result = Set-ServerService -Action Start
        [System.Windows.Forms.MessageBox]::Show($result, "Service Control")
        $refreshButton.PerformClick()
    })
    $serviceGroup.Controls.Add($startButton)

    # Stop button
    $stopButton = New-Object System.Windows.Forms.Button
    $stopButton.Location = New-Object System.Drawing.Point(120, 30)
    $stopButton.Size = New-Object System.Drawing.Size(100, 30)
    $stopButton.Text = "Stop"
    $stopButton.BackColor = [System.Drawing.Color]::Red
    $stopButton.ForeColor = [System.Drawing.Color]::White
    $stopButton.Add_Click({
        $result = Set-ServerService -Action Stop
        [System.Windows.Forms.MessageBox]::Show($result, "Service Control")
        $refreshButton.PerformClick()
    })
    $serviceGroup.Controls.Add($stopButton)

    # Restart button
    $restartButton = New-Object System.Windows.Forms.Button
    $restartButton.Location = New-Object System.Drawing.Point(230, 30)
    $restartButton.Size = New-Object System.Drawing.Size(100, 30)
    $restartButton.Text = "Restart"
    $restartButton.BackColor = [System.Drawing.Color]::Orange
    $restartButton.ForeColor = [System.Drawing.Color]::White
    $restartButton.Add_Click({
        $result = Set-ServerService -Action Restart
        [System.Windows.Forms.MessageBox]::Show($result, "Service Control")
        $refreshButton.PerformClick()
    })
    $serviceGroup.Controls.Add($restartButton)

    # User Management Group
    $userGroup = New-Object System.Windows.Forms.GroupBox
    $userGroup.Location = New-Object System.Drawing.Point(10, 270)
    $userGroup.Size = New-Object System.Drawing.Size(660, 120)
    $userGroup.Text = "User Management"
    $form.Controls.Add($userGroup)

    # Username
    $userLabel = New-Object System.Windows.Forms.Label
    $userLabel.Location = New-Object System.Drawing.Point(10, 25)
    $userLabel.Size = New-Object System.Drawing.Size(80, 20)
    $userLabel.Text = "Username:"
    $userGroup.Controls.Add($userLabel)

    $userTextBox = New-Object System.Windows.Forms.TextBox
    $userTextBox.Location = New-Object System.Drawing.Point(90, 23)
    $userTextBox.Size = New-Object System.Drawing.Size(150, 20)
    $userGroup.Controls.Add($userTextBox)

    # Password
    $passLabel = New-Object System.Windows.Forms.Label
    $passLabel.Location = New-Object System.Drawing.Point(250, 25)
    $passLabel.Size = New-Object System.Drawing.Size(70, 20)
    $passLabel.Text = "Password:"
    $userGroup.Controls.Add($passLabel)

    $passTextBox = New-Object System.Windows.Forms.TextBox
    $passTextBox.Location = New-Object System.Drawing.Point(320, 23)
    $passTextBox.Size = New-Object System.Drawing.Size(150, 20)
    $passTextBox.UseSystemPasswordChar = $true
    $userGroup.Controls.Add($passTextBox)

    # Role
    $roleLabel = New-Object System.Windows.Forms.Label
    $roleLabel.Location = New-Object System.Drawing.Point(10, 55)
    $roleLabel.Size = New-Object System.Drawing.Size(80, 20)
    $roleLabel.Text = "Role:"
    $userGroup.Controls.Add($roleLabel)

    $roleComboBox = New-Object System.Windows.Forms.ComboBox
    $roleComboBox.Location = New-Object System.Drawing.Point(90, 53)
    $roleComboBox.Size = New-Object System.Drawing.Size(150, 20)
    $roleComboBox.DropDownStyle = "DropDownList"
    $roleComboBox.Items.AddRange(@("administrator", "reader", "analyst", "investigator"))
    $roleComboBox.SelectedIndex = 0
    $userGroup.Controls.Add($roleComboBox)

    # Add User button
    $addUserButton = New-Object System.Windows.Forms.Button
    $addUserButton.Location = New-Object System.Drawing.Point(250, 51)
    $addUserButton.Size = New-Object System.Drawing.Size(100, 25)
    $addUserButton.Text = "Add User"
    $addUserButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($userTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a username.", "Validation Error")
            return
        }

        $result = Add-ServerUser -Username $userTextBox.Text `
            -Password $passTextBox.Text `
            -Role $roleComboBox.SelectedItem

        [System.Windows.Forms.MessageBox]::Show($result, "User Management")

        # Clear fields
        $userTextBox.Clear()
        $passTextBox.Clear()
    })
    $userGroup.Controls.Add($addUserButton)

    # Client Package Group
    $clientGroup = New-Object System.Windows.Forms.GroupBox
    $clientGroup.Location = New-Object System.Drawing.Point(10, 400)
    $clientGroup.Size = New-Object System.Drawing.Size(660, 100)
    $clientGroup.Text = "Client Package Generation"
    $form.Controls.Add($clientGroup)

    # Output path
    $outputLabel = New-Object System.Windows.Forms.Label
    $outputLabel.Location = New-Object System.Drawing.Point(10, 30)
    $outputLabel.Size = New-Object System.Drawing.Size(80, 20)
    $outputLabel.Text = "Output Path:"
    $clientGroup.Controls.Add($outputLabel)

    $outputTextBox = New-Object System.Windows.Forms.TextBox
    $outputTextBox.Location = New-Object System.Drawing.Point(90, 28)
    $outputTextBox.Size = New-Object System.Drawing.Size(450, 20)
    $outputTextBox.Text = "C:\Temp"
    $clientGroup.Controls.Add($outputTextBox)

    # Browse button
    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Location = New-Object System.Drawing.Point(550, 26)
    $browseButton.Size = New-Object System.Drawing.Size(80, 24)
    $browseButton.Text = "Browse..."
    $browseButton.Add_Click({
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Select output directory for client MSI"
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $outputTextBox.Text = $folderBrowser.SelectedPath
        }
    })
    $clientGroup.Controls.Add($browseButton)

    # Create MSI button
    $createMSIButton = New-Object System.Windows.Forms.Button
    $createMSIButton.Location = New-Object System.Drawing.Point(10, 60)
    $createMSIButton.Size = New-Object System.Drawing.Size(150, 25)
    $createMSIButton.Text = "Create Client MSI"
    $createMSIButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($outputTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter an output path.", "Validation Error")
            return
        }

        $result = New-ClientMSI -OutputPath $outputTextBox.Text
        [System.Windows.Forms.MessageBox]::Show($result, "Client MSI Creation")
    })
    $clientGroup.Controls.Add($createMSIButton)

    # Configuration Group
    $configGroup = New-Object System.Windows.Forms.GroupBox
    $configGroup.Location = New-Object System.Drawing.Point(10, 510)
    $configGroup.Size = New-Object System.Drawing.Size(660, 60)
    $configGroup.Text = "Configuration"
    $form.Controls.Add($configGroup)

    # Config path
    $configPathLabel = New-Object System.Windows.Forms.Label
    $configPathLabel.Location = New-Object System.Drawing.Point(10, 25)
    $configPathLabel.Size = New-Object System.Drawing.Size(100, 20)
    $configPathLabel.Text = "Config Path:"
    $configGroup.Controls.Add($configPathLabel)

    $configPathTextBox = New-Object System.Windows.Forms.TextBox
    $configPathTextBox.Location = New-Object System.Drawing.Point(110, 23)
    $configPathTextBox.Size = New-Object System.Drawing.Size(430, 20)
    $configPathTextBox.Text = $script:ConfigPath
    $configPathTextBox.ReadOnly = $true
    $configGroup.Controls.Add($configPathTextBox)

    # Edit config button
    $editConfigButton = New-Object System.Windows.Forms.Button
    $editConfigButton.Location = New-Object System.Drawing.Point(550, 21)
    $editConfigButton.Size = New-Object System.Drawing.Size(80, 24)
    $editConfigButton.Text = "Edit"
    $editConfigButton.Add_Click({
        if (Test-Path $script:ConfigPath) {
            Start-Process notepad.exe -ArgumentList $script:ConfigPath
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Configuration file not found.", "Error")
        }
    })
    $configGroup.Controls.Add($editConfigButton)

    # Close Button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Location = New-Object System.Drawing.Point(570, 580)
    $closeButton.Size = New-Object System.Drawing.Size(100, 30)
    $closeButton.Text = "Close"
    $closeButton.Add_Click({ $form.Close() })
    $form.Controls.Add($closeButton)

    # Initial status load
    $form.Add_Shown({
        $form.Activate()
        $refreshButton.PerformClick()
    })

    # Show the form
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
