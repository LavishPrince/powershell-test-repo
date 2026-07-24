<#
    .SYNOPSIS
    Installs Chocolatey (if missing), essential Windows tools, and deploys
    the GlazeWM config.

    .DESCRIPTION
    This script ensures Chocolatey is present, then installs:
      - Zed (text editor)
      - GlazeWM (tiling window manager)
      - Flow Launcher (app launcher)

    After installation, it copies the bundled GlazeWM config.yaml to
    ~/.glaze-wm/config.yaml (backing up any existing config first).

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
    @{ Name = 'zed'           ; Description = 'Zed text editor'               },
    @{ Name = 'glazewm'       ; Description = 'GlazeWM tiling window manager' },
    @{ Name = 'alacritty'     ; Description = 'Alacritty terminal emulator'    },
    @{ Name = 'flow-launcher' ; Description = 'Flow Launcher app launcher'    }
)

foreach ($pkg in $packages) {
    $name        = $pkg.Name
    $description = $pkg.Description

    Write-Host "📦 Installing $description ($name) ..." -ForegroundColor Yellow
    try {
        choco install $name -y --limit-output
        Write-Host "✅ Installed $description" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ Failed to install $description ($name): $_"
    }
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

Write-Host "`n🎉 All done!" -ForegroundColor Green
