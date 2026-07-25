<#
    .SYNOPSIS
    Installs Chocolatey (if missing), essential Windows tools, JetBrains Mono
    Nerd Font, and deploys the GlazeWM config.

    .DESCRIPTION
    This script ensures Chocolatey is present, then installs:
      - Zed (text editor)
      - GlazeWM (tiling window manager)
      - Zebar (status bar / menu bar — integrates with GlazeWM)
      - Alacritty (terminal emulator)
      - Flow Launcher (app launcher)
      - Zen Browser

    It also downloads and installs the JetBrains Mono Nerd Font for use with
    Alacritty, and ensures OpenSSH Client is available (installing it if
    needed). After installation, it copies the bundled config files:
      - GlazeWM config to ~/.glaze-wm/config.yaml
      - Zebar config to ~/.glzr/zebar/config.yaml
    (existing configs are backed up first).

    Finally, it generates an Ed25519 SSH key pair (if one doesn't exist),
    starts the ssh-agent Windows service, adds the key, and prints the
    public key so you can add it to GitHub.

    .EXAMPLE
    .\install.ps1

    .NOTES
    Requires Administrator privileges. The script will self-elevate if needed.
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ──────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────

function Test-Admin {
    [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Chocolatey {
    try {
        $null = Get-Command choco -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# ──────────────────────────────────────────────────
# Self-elevate
# ──────────────────────────────────────────────────

if (-not (Test-Admin)) {
    Write-Host '🔒 Administrator privileges required. Relaunching elevated ...'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath PowerShell -ArgumentList $arguments -Verb RunAs -Wait
    exit $LASTEXITCODE
}

Write-Host '✅ Running with Administrator privileges' -ForegroundColor Green

# ──────────────────────────────────────────────────
# Install Chocolatey
# ──────────────────────────────────────────────────

if (-not (Test-Chocolatey)) {
    Write-Host '📦 Chocolatey not found. Installing ...' -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

        $installScript = [System.Net.WebClient]::new().DownloadString(
            'https://community.chocolatey.org/install.ps1'
        )
        Invoke-Expression $installScript

        # Refresh environment so choco is available in the current session
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                     [System.Environment]::GetEnvironmentVariable('Path', 'User')

        Write-Host '✅ Chocolatey installed successfully' -ForegroundColor Green
    }
    catch {
        Write-Error "❌ Failed to install Chocolatey: $_"
        exit 1
    }
}
else {
    Write-Host '✅ Chocolatey is already installed' -ForegroundColor Green
}

# ──────────────────────────────────────────────────
# Install packages
# ──────────────────────────────────────────────────

$packages = @(
    @{ Name = 'zed'           ; Description = 'Zed text editor'               ; ExtraArgs = ''    },
    @{ Name = 'glazewm'       ; Description = 'GlazeWM tiling window manager' ; ExtraArgs = ''    },
    @{ Name = 'zebar'         ; Description = 'Zebar status bar'              ; ExtraArgs = ''    },
    @{ Name = 'alacritty'     ; Description = 'Alacritty terminal emulator'    ; ExtraArgs = ''    },
    @{ Name = 'flow-launcher' ; Description = 'Flow Launcher app launcher'    ; ExtraArgs = ''    },
    @{ Name = 'zen-browser'   ; Description = 'Zen Browser'                   ; ExtraArgs = '--pre' }
)

foreach ($pkg in $packages) {
    $name        = $pkg.Name
    $description = $pkg.Description
    $extraArgs   = $pkg.ExtraArgs

    Write-Host "📦 Installing $description ($name) ..." -ForegroundColor Yellow
    try {
        choco install $name -y --limit-output $extraArgs
        Write-Host "✅ Installed $description" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ Failed to install $description ($name): $_"
    }
}

# ──────────────────────────────────────────────────
# Install JetBrains Mono Nerd Font (for Alacritty)
# ──────────────────────────────────────────────────

Write-Host '🔤 Installing JetBrains Mono Nerd Font ...' -ForegroundColor Yellow

try {
    choco install nerd-fonts-JetBrainsMono -y --limit-output
    Write-Host '✅ JetBrains Mono Nerd Font installed' -ForegroundColor Green
}
catch {
    Write-Error "❌ Failed to install JetBrains Mono Nerd Font: $_"
}

# ──────────────────────────────────────────────────
# Deploy Alacritty config (Windows)
# ──────────────────────────────────────────────────

$alacrittySrcDir  = Join-Path $PSScriptRoot 'home' '.config' 'alacritty'
$alacrittyDestDir = Join-Path $env:APPDATA 'alacritty'

if (Test-Path $alacrittySrcDir) {
    Write-Host '⚙️  Deploying Alacritty config ...' -ForegroundColor Yellow

    if (-not (Test-Path $alacrittyDestDir)) {
        New-Item -ItemType Directory -Path $alacrittyDestDir -Force | Out-Null
    }

    # Copy themes directory (include gitignored submodules)
    $themesSrc = Join-Path $alacrittySrcDir 'themes'
    if (Test-Path $themesSrc) {
        $themesDest = Join-Path $alacrittyDestDir 'themes'
        if (Test-Path $themesDest) { Remove-Item $themesDest -Recurse -Force }
        Copy-Item $themesSrc $themesDest -Recurse -Force
        Write-Host '   Copied themes'
    }

    # Copy config, rewriting the import path for Windows
    $configSrc  = Join-Path $alacrittySrcDir 'alacritty.toml'
    $configDest = Join-Path $alacrittyDestDir 'alacritty.toml'

    $configContent = Get-Content $configSrc -Raw
    # Replace Unix-style ~/.config/alacritty import with a relative path
    $configContent = $configContent -replace
        '~/.config/alacritty/themes/',
        'themes/'

    # Backup existing config if present
    if (Test-Path $configDest) {
        $backupPath = "$configDest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $configDest $backupPath
        Write-Host "   Backed up existing config to $backupPath"
    }

    Set-Content -Path $configDest -Value $configContent -NoNewline
    Write-Host '✅ Alacritty config deployed' -ForegroundColor Green
}
else {
    Write-Warning 'home/.config/alacritty not found next to this script — skipping Alacritty config deploy'
}

# ──────────────────────────────────────────────────
# Deploy GlazeWM config
# ──────────────────────────────────────────────────

$glazeWmDir  = Join-Path $env:USERPROFILE '.glaze-wm'
$configSrc   = Join-Path $PSScriptRoot 'glazewm' 'config.yaml'
$configDest  = Join-Path $glazeWmDir 'config.yaml'

if (Test-Path $configSrc) {
    Write-Host '⚙️  Deploying GlazeWM config ...' -ForegroundColor Yellow

    if (-not (Test-Path $glazeWmDir)) {
        New-Item -ItemType Directory -Path $glazeWmDir -Force | Out-Null
        Write-Host "   Created $glazeWmDir"
    }

    # Backup existing config if present
    if (Test-Path $configDest) {
        $backupPath = "$configDest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $configDest $backupPath
        Write-Host "   Backed up existing config to $backupPath"
    }

    Copy-Item $configSrc $configDest -Force
    Write-Host '✅ GlazeWM config deployed' -ForegroundColor Green
}
else {
    Write-Warning 'glazewm/config.yaml not found next to this script — skipping config deploy'
}

# ──────────────────────────────────────────────────
# Deploy Zebar config
# ──────────────────────────────────────────────────

$zebarDir  = Join-Path $env:USERPROFILE '.glzr' 'zebar'
$configSrc  = Join-Path $PSScriptRoot 'zebar' 'config.yaml'
$configDest = Join-Path $zebarDir 'config.yaml'

if (Test-Path $configSrc) {
    Write-Host '⚙️  Deploying Zebar config ...' -ForegroundColor Yellow

    if (-not (Test-Path $zebarDir)) {
        New-Item -ItemType Directory -Path $zebarDir -Force | Out-Null
        Write-Host "   Created $zebarDir"
    }

    # Backup existing config if present
    if (Test-Path $configDest) {
        $backupPath = "$configDest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $configDest $backupPath
        Write-Host "   Backed up existing config to $backupPath"
    }

    Copy-Item $configSrc $configDest -Force
    Write-Host '✅ Zebar config deployed' -ForegroundColor Green
}
else {
    Write-Warning 'zebar/config.yaml not found next to this script — skipping config deploy'
}

# ──────────────────────────────────────────────────
# Ensure OpenSSH Client is available
# ──────────────────────────────────────────────────

$sshKeygenPath = (Get-Command ssh-keygen -ErrorAction SilentlyContinue).Source

if (-not $sshKeygenPath) {
    Write-Host '🔑 OpenSSH Client not found. Installing via Windows Optional Feature ...' -ForegroundColor Yellow
    try {
        # Dynamically discover the exact capability name (avoids hardcoding version)
        $capability = Get-WindowsCapability -Online |
            Where-Object { $_.Name -like 'OpenSSH.Client*' } |
            Select-Object -First 1

        if (-not $capability) {
            throw 'OpenSSH.Client capability not found on this system'
        }

        if ($capability.State -eq 'Installed') {
            Write-Host '✅ OpenSSH Client is already installed' -ForegroundColor Green
        }
        else {
            Write-Host "   Installing capability: $($capability.Name) ..."
            Add-WindowsCapability -Online -Name $capability.Name
        }

        # Refresh PATH so ssh-keygen is available immediately
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                     [System.Environment]::GetEnvironmentVariable('Path', 'User')
        Write-Host '✅ OpenSSH Client ready' -ForegroundColor Green
    }
    catch {
        Write-Error "❌ Failed to install OpenSSH Client: $_"
        Write-Host '   Install it manually: Settings → Apps → Optional Features → Add a feature → OpenSSH Client'
        Write-Host '   Or run: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0'
    }
}
else {
    Write-Host "✅ OpenSSH Client found at $sshKeygenPath" -ForegroundColor Green
}

# ──────────────────────────────────────────────────
# Generate SSH key pair for GitHub
# ──────────────────────────────────────────────────

$sshDir  = Join-Path $env:USERPROFILE '.ssh'
$keyPath = Join-Path $sshDir 'id_ed25519'

# Only proceed if ssh-keygen is available
if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
    Write-Host '🔑 Checking for existing SSH key ...' -ForegroundColor Yellow

    if (Test-Path $keyPath) {
        Write-Host '✅ SSH key already exists at' $keyPath -ForegroundColor Green
    }
    else {
        Write-Host '🔑 No existing SSH key found. Generating a new Ed25519 key pair ...' -ForegroundColor Yellow

        # Ensure .ssh directory exists
        if (-not (Test-Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }

        # Prompt for an optional passphrase
        $usePassphrase = Read-Host '🔒 Enter a passphrase for your SSH key (or press Enter to skip)'

        try {
            if ([string]::IsNullOrWhiteSpace($usePassphrase)) {
                # Generate key without passphrase ('""' passes empty string to ssh-keygen)
                ssh-keygen -t ed25519 -C "$env:USERNAME@github" -f $keyPath -N '""' 2>&1 | Out-Null
            }
            else {
                ssh-keygen -t ed25519 -C "$env:USERNAME@github" -f $keyPath -N "$usePassphrase" 2>&1 | Out-Null
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Host '✅ SSH key pair generated successfully' -ForegroundColor Green
            }
            else {
                throw "ssh-keygen exited with code $LASTEXITCODE"
            }
        }
        catch {
            Write-Error "❌ Failed to generate SSH key: $_"
        }
    }

    # ──────────────────────────────────────────────────
    # Start ssh-agent service and add the key
    # ──────────────────────────────────────────────────

    Write-Host '🔐 Ensuring OpenSSH Authentication Agent service is running ...' -ForegroundColor Yellow

    try {
        $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue

        if (-not $svc) {
            Write-Warning '⚠️  ssh-agent service not found. You may need to install OpenSSH Client.'
        }
        else {
            # Set startup type to Automatic so it persists across reboots
            if ($svc.StartType -ne 'Automatic') {
                Set-Service ssh-agent -StartupType Automatic
                Write-Host '   Set ssh-agent service startup to Automatic'
            }

            # Start the service if not already running
            if ($svc.Status -ne 'Running') {
                Start-Service ssh-agent
                Write-Host '   ssh-agent service started'
            }
            else {
                Write-Host '   ssh-agent service is already running'
            }

            # Add the key to ssh-agent
            ssh-add $keyPath 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host '✅ SSH key added to ssh-agent' -ForegroundColor Green
            }
            else {
                Write-Warning '⚠️  Could not add key to ssh-agent. You may need to add it manually: ssh-add ~/.ssh/id_ed25519'
            }
        }
    }
    catch {
        Write-Warning "⚠️  ssh-agent setup issue: $_"
    }

    # ──────────────────────────────────────────────────
    # Display public key for GitHub
    # ──────────────────────────────────────────────────

    $pubKeyPath = "$keyPath.pub"

    if (Test-Path $pubKeyPath) {
        Write-Host "`n📋 Your public SSH key (add this to GitHub → Settings → SSH and GPG keys):" -ForegroundColor Cyan
        Write-Host ('─' * 72)
        Get-Content $pubKeyPath | ForEach-Object { Write-Host $_ -ForegroundColor White }
        Write-Host ('─' * 72)
        Write-Host '   ➡️  https://github.com/settings/keys' -ForegroundColor DarkCyan
    }
}

Write-Host "`n🎉 All done!" -ForegroundColor Green
