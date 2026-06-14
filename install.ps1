[CmdletBinding()]
param(
    [string]$DistroName = 'Exherbo',
    [string]$InstallPath = 'C:\WSL\exherbo',
    [string]$DownloadDir = 'C:\WSL\downloads',
    [string]$Username = $env:USERNAME.ToLower(),
    [string]$Hostname = "$env:COMPUTERNAME-exherbo".ToLower(),
    [string]$Timezone = 'America/New_York',
    [string]$StageUrl = 'https://stages.exherbo.org/x86_64-pc-linux-gnu/exherbo-x86_64-pc-linux-gnu-gcc-current.tar.xz',
    [switch]$EnableMarv,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Say([string]$msg) { Write-Host "[exherbo-wsl2] $msg" -ForegroundColor Cyan }
function OK ([string]$msg) { Write-Host "[OK] $msg"          -ForegroundColor Green }
function Warn([string]$msg) { Write-Host "[WARN] $msg"       -ForegroundColor Yellow }
function Fail([string]$msg) { Write-Host "[FAIL] $msg"       -ForegroundColor Red; exit 1 }

$WSL = "$env:WINDIR\System32\wsl.exe"

# ---- 1. preflight ----
Say "preflight"

function Install-WSL-IfMissing {
    # Test whether WSL is actually usable. Two failure modes:
    # will let you know if wsl.exe is missing (WSL feature not enabled) or if wsl.exe is present but WSL2 isn't working (kernel missing, etc).
    $wslOk = $false
    if (Test-Path $WSL) {
        try {
            $null = & $WSL --version 2>&1
            if ($LASTEXITCODE -eq 0) { $wslOk = $true }
        } catch { }
    }
    if ($wslOk) { return }

    Warn "WSL2 doesn't look usable on this machine (wsl.exe missing or feature not enabled)."
    Write-Host ""
    Write-Host "  To install WSL2 we need to run, as ADMINISTRATOR:" -ForegroundColor Yellow
    Write-Host "      wsl --install --no-distribution"
    Write-Host ""
    Write-Host "  This enables the WSL Windows feature, downloads the WSL2 kernel,"
    Write-Host "  and may require a REBOOT before this installer can proceed."
    Write-Host ""
    $resp = Read-Host "Run it now with elevation? (y/N)"
    if ($resp -ne 'y') {
        Fail "Aborting. Install WSL manually (wsl --install) then re-run this script."
    }

    # Relaunch with elevation to run the wsl --install
    $proc = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList '-NoProfile','-Command','wsl --install --no-distribution; Write-Host ""; Read-Host "Press Enter to close"' `
        -Verb RunAs -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        Fail "wsl --install returned $($proc.ExitCode). Resolve the error and re-run this script."
    }

    Write-Host ""
    Write-Host "  WSL install requested. If Windows asked for a reboot, REBOOT FIRST" -ForegroundColor Yellow
    Write-Host "  then re-run this installer." -ForegroundColor Yellow
    Write-Host ""
    $resp2 = Read-Host "Skip reboot and try to continue now? (y/N)"
    if ($resp2 -ne 'y') { exit 0 }
}

Install-WSL-IfMissing

try {
    $null = & $WSL --version 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "wsl --version still failing after install attempt. Reboot and try again." }
} catch { Fail "wsl --version threw: $_" }
OK "wsl available"

$existing = (& $WSL --list --quiet 2>&1) -replace "`0", '' | Where-Object { $_ -match $DistroName }
if ($existing -and -not $Force) {
    Warn "distro '$DistroName' is already registered."
    $resp = Read-Host "Unregister and reinstall? (y/N)"
    if ($resp -ne 'y') { Say "aborting (use -Force to skip this prompt)"; exit 0 }
    & $WSL --unregister $DistroName 2>&1 | Out-Null
    OK "old '$DistroName' unregistered"
}

# ---- 1b. interactive username + password ----
# Default username = Windows username lower-cased, but let the user override.
Write-Host ""
Say "user setup"
$usernameInput = Read-Host "Linux username [$Username]"
if (-not [string]::IsNullOrWhiteSpace($usernameInput)) {
    $Username = $usernameInput
}
# Cheap sanity: must start with a letter, only [a-z0-9_-] allowed, <= 32 chars.
if ($Username -notmatch '^[a-z][a-z0-9_-]{0,31}$') {
    Fail "Username '$Username' is invalid (lowercase letter start, then [a-z0-9_-], <=32 chars)"
}

# Prompt for a password (>= 8 chars; PAM rejects shorter). Same for root.
function Read-PlaintextPassword([string]$prompt) {
    while ($true) {
        $sec1 = Read-Host -Prompt $prompt -AsSecureString
        $sec2 = Read-Host -Prompt "  re-enter to confirm" -AsSecureString
        $b1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec1)
        $b2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2)
        try {
            $p1 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
            $p2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
        }
        if ($p1 -ne $p2) { Warn "passwords don't match; try again"; continue }
        if ($p1.Length -lt 8) { Warn "password must be at least 8 chars; try again"; continue }
        if ($p1 -match "[`r`n']") { Warn "password can't contain newlines or single quotes; try again"; continue }
        return $p1
    }
}

$UserPassword = Read-PlaintextPassword "Password for '$Username'"
$useSamePw = Read-Host "Use the same password for root? (Y/n)"
if ($useSamePw -eq 'n' -or $useSamePw -eq 'N') {
    $RootPassword = Read-PlaintextPassword "Password for root"
} else {
    $RootPassword = $UserPassword
}
OK "credentials captured"

# ---- 2. download stage ----
Say "preparing dirs"
New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
if ((Get-ChildItem $InstallPath -Force -ErrorAction SilentlyContinue).Count -gt 0 -and -not $Force) {
    Fail "$InstallPath is not empty. Use -Force or pick a different -InstallPath."
}

$stageFile = Join-Path $DownloadDir 'exherbo-stage.tar.xz'
$hashFile  = "$stageFile.sha256"

function Get-Sha256Hex([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::OpenRead($path)
        try {
            $bytes = $sha.ComputeHash($fs)
        } finally { $fs.Dispose() }
    } finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($bytes) -replace '-','').ToLower()
}

# Always fetch the current upstream hash so we can validate a cached tarball.
Say "downloading hash file"
Invoke-WebRequest -Uri "$StageUrl.sha256sum" -OutFile $hashFile -UseBasicParsing
$claimed = (Get-Content $hashFile -Raw).Trim().Split()[0]
OK "got hash file ($claimed)"

# Reuse a cached tarball iff it hashes to the upstream value. Otherwise re-download.
$needDownload = $true
if (Test-Path $stageFile) {
    Say "checking cached tarball at $stageFile"
    $cachedHash = Get-Sha256Hex $stageFile
    if ($cachedHash -eq $claimed.ToLower()) {
        $mb = [math]::Round((Get-Item $stageFile).Length / 1MB, 1)
        OK "cached tarball matches upstream hash ($mb MB) -- skipping download"
        $needDownload = $false
    } else {
        Warn "cached tarball hash mismatch -- redownloading"
    }
}

if ($needDownload) {
    Say "downloading stage tarball (~560 MB)"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-WebRequest -Uri $StageUrl -OutFile $stageFile -UseBasicParsing
    $sw.Stop()
    $mb = [math]::Round((Get-Item $stageFile).Length / 1MB, 1)
    OK "downloaded $mb MB in $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
}

Say "verifying sha256"
$actual = Get-Sha256Hex $stageFile
if ($claimed.ToLower() -ne $actual) {
    Fail "SHA256 MISMATCH. Expected $claimed, got $actual. Delete $stageFile and retry."
}
OK "sha256 verified ($actual)"

# ---- 3. wsl import ----
Say "wsl --import $DistroName"
$swImport = [System.Diagnostics.Stopwatch]::StartNew()
& $WSL --import $DistroName $InstallPath $stageFile --version 2 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "wsl --import failed (rc=$LASTEXITCODE)" }
$swImport.Stop()
OK "imported in $([math]::Round($swImport.Elapsed.TotalSeconds,1))s"

# ---- 4. first-boot setup inside the distro ----
Say "writing /etc/wsl.conf, creating user '$Username', cave sync"

# The setup script that runs INSIDE the distro as root.
# Variables interpolated from PowerShell:
#   $u   -- username
#   $h   -- hostname
#   $tz  -- timezone
#   $m   -- 1 if -EnableMarv was passed, else 0
#   $rpw -- root password (captured interactively)
#   $upw -- user password (captured interactively)
$u   = $Username
$h   = $Hostname
$tz  = $Timezone
$m   = if ($EnableMarv) { '1' } else { '0' }
$rpw = $RootPassword
$upw = $UserPassword

$setupScript = @"
set -e

# /etc/wsl.conf
cat > /etc/wsl.conf << 'EOF'
[boot]
systemd=false

[user]
default=$u

[network]
generateHosts=true
generateResolvConf=true

[interop]
# enabled=true keeps explorer.exe / code.exe / etc. callable when you
# explicitly want to cross over to Windows.
enabled=true
# but appendWindowsPath=false stops Windows PATH from being unionised
# into the Linux PATH -- so `kcc` resolves to the Linux install, never
# to C:\Users\...\kcc.exe.
appendWindowsPath=false

[automount]
enabled=true
# noexec on /mnt/c blocks executing Windows binaries from inside WSL even
# if you call them by full path -- prevents accidentally running a stray
# Windows kcc.exe / etc.exe when you meant the Linux native version.
# Read + list still work, so cd /mnt/c/... is fine for inspection.
options="metadata,umask=22,fmask=11,noexec"
EOF

# hostname + timezone
echo '$h' > /etc/hostname
ln -sf /usr/share/zoneinfo/$tz /etc/localtime 2>/dev/null || true
echo '$tz' > /etc/timezone 2>/dev/null || true

# Passwords captured interactively on the Windows side (PAM here enforces
# >=8 chars). The installer validates length + matching on input, so by
# the time we get here the values are safe to use directly.
echo 'root:$rpw' | chpasswd
useradd -m -G wheel,users -s /bin/bash $u
echo "${u}:$upw" | chpasswd

# enable wheel sudo (sudoers exists post-stage)
[ -f /etc/sudoers ] && sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# initial sync of all configured repos
echo "--- cave sync ---"
cave sync 2>&1 | tail -20

# optionally enable marv
if [ "$m" = "1" ]; then
    echo "--- enabling marv repository ---"
    cave resolve -x repository/marv 2>&1 | tail -5
    cave sync marv 2>&1 | tail -5
fi

echo "--- setup done ---"
"@

$tmpScript = Join-Path $env:TEMP "exherbo-setup-$([Guid]::NewGuid().ToString('N').Substring(0,8)).sh"
# Set-Content -Encoding UTF8 in PS 5.1 prepends a BOM which bash chokes on,
# and the PowerShell here-string uses Windows CRLF line endings which bash
# also chokes on (sees `set -e\r` -> `-e\r` as an invalid flag). Normalise
# both before writing.
$setupScript = $setupScript -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($tmpScript, $setupScript, [System.Text.UTF8Encoding]::new($false))

# Convert Windows path -> WSL path via the distro's wslpath
$wslPath = (& $WSL -d $DistroName -u root -e wslpath -u "$tmpScript" 2>&1).Trim()
if ([string]::IsNullOrWhiteSpace($wslPath)) {
    Fail "wslpath returned empty for $tmpScript"
}
& $WSL -d $DistroName -u root -- bash "$wslPath" 2>&1 | Tee-Object -Variable setupOut | Out-Host
if ($LASTEXITCODE -ne 0) { Fail "in-distro setup failed (rc=$LASTEXITCODE)" }
Remove-Item -Path $tmpScript -Force -ErrorAction SilentlyContinue
OK "in-distro setup complete"

# ---- 5. bounce + verify ----
Say "bouncing distro so default user takes effect"
& $WSL --terminate $DistroName 2>&1 | Out-Null
Start-Sleep -Seconds 2

Say "smoke test"

try {
    & $WSL -d $DistroName -- bash -c 'echo "user=$(whoami) uid=$(id -u)"; cave --version | head -1' 2>&1 | Out-Host
} catch {
    Warn "smoke test threw: $_  (distro is probably fine - manually verify with: wsl -d $DistroName)"
}

# ---- 6. summary ----
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  Exherbo installed and ready"             -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  Distro:    $DistroName"
Write-Host "  Path:      $InstallPath"
Write-Host "  User:      $Username (password you set during install)"
Write-Host "  Root:      password you set during install"
Write-Host "  Hostname:  $h"
Write-Host ""
Write-Host "  CHANGE THOSE PLACEHOLDER PASSWORDS:" -ForegroundColor Yellow
Write-Host "    wsl -d $DistroName -- passwd"
Write-Host "    wsl -d $DistroName -u root -- passwd"
Write-Host ""
Write-Host "  Run with:  wsl -d $DistroName"
Write-Host ""
Write-Host "  Useful cave commands:"
Write-Host "    cave show <pkg>          info about a package"
Write-Host "    cave resolve <pkg>       dry-run install"
Write-Host "    cave resolve -x <pkg>    actually install"
Write-Host "    cave sync                resync all repos"
Write-Host "    eclectic news read       read news items"
Write-Host ""
if (-not $EnableMarv) {
    Write-Host "  Tip: re-run with -EnableMarv to add the marv community repo"
    Write-Host "       (or do it manually:  sudo cave resolve -x repository/marv)"
    Write-Host ""
}
