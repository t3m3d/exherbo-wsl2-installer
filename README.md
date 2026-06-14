<img width="990" height="509" alt="image" src="https://github.com/user-attachments/assets/275d890b-f886-4f4e-9673-4d45461a3afe" />
# exherbo-wsl2-installer

One-shot installer for [Exherbo Linux](https://www.exherbo.org/) on WSL2.

Exherbo is a source-based, opinionated, hand-curated distribution by ex-Gentoo
developers. Notoriously fiddly to install — no installer, you bootstrap from a
stage tarball and configure everything by hand. This script automates the
whole flow.

## Quick start (easiest path)

**On a Windows 11 machine**:

1. Download this repo as a ZIP from GitHub
   ([direct link](https://github.com/t3m3d/exherbo-wsl2-installer/archive/refs/heads/main.zip))
   and extract it anywhere.
2. **Double-click `run.cmd`** in the extracted folder.
3. Watch the PowerShell window. When it says "Exherbo installed and ready",
   you're done.
4. Open a regular PowerShell and run: `wsl -d Exherbo`

`run.cmd` handles the two friction points that bite first-time users:
PowerShell blocks unsigned `.ps1` files by default, and double-clicking
a `.ps1` opens Notepad instead of running it. `run.cmd` runs `install.ps1`
through PowerShell with the right flags, in a window that stays open so
you can read the output.

If WSL2 isn't installed yet on the machine, the script will detect that,
ask permission, and run `wsl --install` for you (with a UAC prompt). After
that you may need to **reboot once** and re-run.

If you prefer the terminal path, scroll to [Usage](#usage) below.

## What it does

1. Verifies WSL2 is installed
2. Downloads the latest `x86_64-pc-linux-gnu` stage tarball (~560 MB) from
   the official mirror
3. SHA256-verifies it against the published checksum
4. `wsl --import` to register the distro
5. Inside the new distro: writes `/etc/wsl.conf`, creates a non-root user
   in the `wheel` group with sudo enabled, sets hostname + timezone,
   runs `cave sync` for all 10 default repositories
6. Bounces WSL so the default-user setting takes effect
7. Smoke-tests the result (user check, `cave --version`, `sudo` check)

## Usage

Open a PowerShell prompt (regular user is fine — WSL doesn't need admin):

```powershell
# All defaults: distro name "Exherbo", install to C:\WSL\exherbo,
# user = your Windows username (lowercased), timezone America/New_York
.\install.ps1

# Customize
.\install.ps1 -DistroName Exherbo2 -InstallPath D:\WSL\exherbo -Username alice

# Set a different timezone
.\install.ps1 -Timezone Europe/Berlin

# Enable the marv community repository (for packages like neofetch)
.\install.ps1 -EnableMarv

# Force overwrite an existing install of the same name
.\install.ps1 -Force
```

## Parameters

| Parameter | Default | Notes |
|---|---|---|
| `-DistroName` | `Exherbo` | What `wsl --list` will call it |
| `-InstallPath` | `C:\WSL\exherbo` | Where the `.vhdx` lives |
| `-DownloadDir` | `C:\WSL\downloads` | Where the stage tarball is cached |
| `-Username` | `$env:USERNAME` (lowercased) | The non-root account it creates |
| `-Hostname` | `<computer>-exherbo` (lowercased) | `/etc/hostname` value |
| `-Timezone` | `America/New_York` | Any zoneinfo name (`Europe/Berlin`, `Asia/Tokyo`, ...) |
| `-StageUrl` | latest amd64 GCC `-current` | Hardcoded to the `-current` symlink so it doesn't go stale |
| `-EnableMarv` | off | Adds the `marv` community repo (neofetch + many others live there) |
| `-Force` | off | Skip the "already-installed, overwrite?" prompt |

## After it finishes

The script prints a summary with credentials and quick-start hints. **Change
the placeholder passwords immediately:**

```powershell
wsl -d Exherbo -- passwd                # change your user password
wsl -d Exherbo -u root -- passwd        # change the root password
```

Default placeholder passwords are intentionally trivial (same as the username,
root is `exherbo`) so the install is non-interactive.

## Useful `cave` commands

Exherbo uses [Paludis](https://paludis.exherbo.org/) and its CLI is `cave`,
not `emerge` or `apt`:

```bash
cave show <pkg>              # info about a package
cave resolve <pkg>           # dry-run install (shows what would happen)
cave resolve -x <pkg>        # actually install
cave sync                    # resync all repositories
cave sync marv               # sync just one
eclectic news read           # read news items
```

To install a package from the `unavailable` repository (i.e. it exists but
isn't in a repo you have synced), find the repo name in the error message
(e.g. `::marv`) and enable that repo:

```bash
sudo cave resolve -x repository/marv
sudo cave sync
sudo cave resolve -x <pkg>
```

## Requirements

- Windows 10 22H2 or later, or Windows 11
- WSL2 already installed and the default version (`wsl --set-default-version 2`)
- ~1 GB free in `C:\WSL\downloads\` for the stage tarball
- ~3 GB free in `C:\WSL\exherbo\` for the live distro (grows as you install)
- Internet — script downloads ~560 MB

## Safety

- SHA256 verification: download is checked against the published `.sha256sum`
  before import. Mismatch aborts the script.
- Existing-distro detection: re-running won't silently clobber an existing
  install — it prompts unless `-Force` is given.
- The setup script that runs inside the distro is generated fresh each run
  into `%TEMP%` and deleted on success; on failure it's left behind for
  debugging.

## How it differs from `wsl --install`

Microsoft's `wsl --install -d <distro>` only works for distros in the WSL
Store. Exherbo isn't there. This script handles the `wsl --import` flow,
which is the path for any distro that ships a rootfs tarball but isn't in
the Store catalog (Gentoo, Void, Alpine, NixOS, Chimera, etc.).

## Companion scripts

This shape (download stage → import → first-boot setup → cave/portage sync
→ user setup) is reusable. If you want a similar installer for another
source-based distro, the structure of `install.ps1` is easy to fork —
swap the URL, the hash-fetch logic, and the package-manager sync command.
