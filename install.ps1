<#
    .SYNOPSIS
    Installs Chocolatey (if missing) and essential Windows tools.

    .DESCRIPTION
    This script ensures Chocolatey is present, then installs:
      - Zed (text editor)
      - GlazeWM (tiling window manager)
      - Flow Launcher (app launcher)

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
    [bool](([Security.Principal.WindowsPrincipal]
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
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

Write-Host "`n🎉 All done!" -ForegroundColor Green
