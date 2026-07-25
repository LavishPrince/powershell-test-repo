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
    Alacritty. After installation, it copies the bundled config files:
      - GlazeWM config to ~/.glaze-wm/config.yaml
      - Zebar config to ~/.glzr/zebar/config.yaml
    (existing configs are backed up first).

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

        # Use Invoke-RestMethod rather than WebClient: it surfaces HTTP/TLS
        # failures as a proper terminating error with a useful message,
        # instead of leaving $installScript unassigned and producing a
        # confusing "variable has not been set" error under strict mode.
        $installScript = $null
        try {
            $installScript = Invoke-RestMethod -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing
        }
        catch {
            throw "Could not download the Chocolatey install script: $_"
        }

        if ([string]::IsNullOrWhiteSpace($installScript)) {
            throw 'Downloaded Chocolatey install script was empty'
        }

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
        if ([string]::IsNullOrWhiteSpace($extraArgs)) {
            choco install $name -y --limit-output
        }
        else {
            choco install $name -y --limit-output $extraArgs
        }
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
    $alacrittyThemesSrc = Join-Path $alacrittySrcDir 'themes'
    if (Test-Path $alacrittyThemesSrc) {
        $alacrittyThemesDest = Join-Path $alacrittyDestDir 'themes'
        if (Test-Path $alacrittyThemesDest) { Remove-Item $alacrittyThemesDest -Recurse -Force }
        Copy-Item $alacrittyThemesSrc $alacrittyThemesDest -Recurse -Force
        Write-Host '   Copied themes'
    }

    # Copy config, rewriting the import path for Windows
    $alacrittyConfigSrc  = Join-Path $alacrittySrcDir 'alacritty.toml'
    $alacrittyConfigDest = Join-Path $alacrittyDestDir 'alacritty.toml'

    $alacrittyConfigContent = Get-Content $alacrittyConfigSrc -Raw
    # Replace Unix-style ~/.config/alacritty import with a relative path
    $alacrittyConfigContent = $alacrittyConfigContent -replace
        '~/.config/alacritty/themes/',
        'themes/'

    # Backup existing config if present
    if (Test-Path $alacrittyConfigDest) {
        $backupPath = "$alacrittyConfigDest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $alacrittyConfigDest $backupPath
        Write-Host "   Backed up existing config to $backupPath"
    }

    Set-Content -Path $alacrittyConfigDest -Value $alacrittyConfigContent -NoNewline
    Write-Host '✅ Alacritty config deployed' -ForegroundColor Green
}
else {
    Write-Warning 'home/.config/alacritty not found next to this script — skipping Alacritty config deploy'
}

# ──────────────────────────────────────────────────
# Deploy GlazeWM config
# ──────────────────────────────────────────────────

$glazeWmDir        = Join-Path $env:USERPROFILE '.glaze-wm'
$glazeWmConfigSrc  = Join-Path $PSScriptRoot 'glazewm' 'config.yaml'
$glazeWmConfigDest = Join-Path $glazeWmDir 'config.yaml'

if (Test-Path $glazeWmConfigSrc) {
    Write-Host '⚙️  Deploying GlazeWM config ...' -ForegroundColor Yellow

    if (-not (Test-Path $glazeWmDir)) {
        New-Item -ItemType Directory -Path $glazeWmDir -Force | Out-Null
        Write-Host "   Created $glazeWmDir"
    }

    # Backup existing config if present
    if (Test-Path $glazeWmConfigDest) {
        $backupPath = "$glazeWmConfigDest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $glazeWmConfigDest $backupPath
        Write-Host "   Backed up existing config to $backupPath"
    }

    Copy-Item $glazeWmConfigSrc $glazeWmConfigDest -Force
    Write-Host '✅ GlazeWM config deployed' -ForegroundColor Green
}
else {
    Write-Warning 'glazewm/config.yaml not found next to this script — skipping config deploy'
}

# ──────────────────────────────────────────────────
# Deploy Zebar config
# ──────────────────────────────────────────────────

$zebarDir        = Join-Path $env:USERPROFILE '.glzr' 'zebar'
$zebarConfigSrc  = Join-Path $PSScriptRoot 'zebar' 'config.yaml'
$zebarConfigDest = Join-Path $zebarDir 'config.yaml'

if (Test-Path $zebarConfigSrc) {
    Write-Host '⚙️  Deploying Zebar config ...' -ForegroundColor Yellow

    if (-not (Test-Path $zebarDir)) {
        New-Item -ItemType Directory -Path $zebarDir -Force | Out-Null
        Write-Host "   Created $zebarDir"
    }

    # Backup existing config if present
    if (Test-Path $zebarConfigDest) {
        $backupPath = "$zebarConfigDest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $zebarConfigDest $backupPath
        Write-Host "   Backed up existing config to $backupPath"
    }

    Copy-Item $zebarConfigSrc $zebarConfigDest -Force
    Write-Host '✅ Zebar config deployed' -ForegroundColor Green
}
else {
    Write-Warning 'zebar/config.yaml not found next to this script — skipping config deploy'
}

Write-Host "`n🎉 All done!" -ForegroundColor Green
