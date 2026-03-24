# Installing /make-it & /ship-it Skills

Add the /make-it and /ship-it Claude skills to Claude Code. No programming experience required.

> **Prerequisite:** You need Claude Code installed before doing this. If you don't have it yet, follow the [Vibe Code Quick Start](../README.md) (macOS) or [Windows Setup Guide](WINDOWS-SETUP.md) (Windows) first.

You can either follow the **simple steps below** one by one, or skip to the [Automate](#automate) section to run a single script that does everything for you.

---

## /make-it

Describe an app idea to Claude and it builds a fully working application for you -- no programming skills required.

### How to Install

**Step 1:** Open a command window.

> **macOS:** Press **Command + Space**, type **Terminal**, click on it.
>
> **Windows:** Click the **Start button**, type **PowerShell**, click on **Windows PowerShell**.

**Step 2:** Copy and paste this, then press Enter:

**macOS:**

```bash
mkdir -p ~/Documents/Github && cd ~/Documents/Github
```

**Windows:**

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\Documents\Github" | Out-Null; Set-Location "$HOME\Documents\Github"
```

**Step 3:** Copy and paste this, then press Enter:

```
git clone https://github.com/SleepNumberInc/make-it.git
```

Wait until you see the blinking cursor again -- this means the download is finished.

**Step 4:** Copy and paste this, then press Enter:

**macOS:**

```bash
cd make-it
```

**Windows:**

```powershell
Set-Location make-it
```

**Step 5:** Copy and paste this, then press Enter:

**macOS:**

```bash
./install.sh
```

**Windows** (two options):

```powershell
.\install.ps1
```

Or remote install (no git clone required):

```powershell
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```

---

## /ship-it

When your app is ready to share, this skill packages it up and delivers it to your team -- one command instead of a manual checklist.

### How to Install

**Step 1:** Go back to your command window (or reopen it if you closed it).

**Step 2:** Copy and paste this, then press Enter:

**macOS:**

```bash
mkdir -p ~/Documents/Github && cd ~/Documents/Github
```

**Windows:**

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\Documents\Github" | Out-Null; Set-Location "$HOME\Documents\Github"
```

**Step 3:** Copy and paste this, then press Enter:

```
git clone https://github.com/SleepNumberInc/ship-it.git
```

Wait until you see the blinking cursor again.

**Step 4:** Copy and paste this, then press Enter:

**macOS:**

```bash
cd ship-it
```

**Windows:**

```powershell
Set-Location ship-it
```

**Step 5:** Copy and paste this, then press Enter:

**macOS:**

```bash
./install.sh
```

**Windows:**

```bash
bash ./install.sh
```

> *If that doesn't work, try:* `Get-Content install.sh | bash`

---

## After Installing

If Claude Code was running during the install, close it and reopen it. Then just type `/make-it` or `/ship-it` and press **Enter**.

---

## Automate

A script that downloads and installs both skills for you in one go.

### macOS

1. Download `install-claude-skills.sh` (see below)
2. Open **Terminal**
3. Copy and paste this, then press **Enter**:

```bash
~/Downloads/install-claude-skills.sh
```

4. Wait until it says "Installation Complete."

> *If you see "Permission denied", run this first:*
>
> ```bash
> chmod +x ~/Downloads/install-claude-skills.sh
> ```
>
> Then try step 3 again.

### Windows

1. Download `install-claude-skills.ps1` (see below)
2. Find the file in your Downloads folder
3. **Right-click** on the file and select **"Run with PowerShell"**
4. Wait until it says "Installation Complete." Press **Enter** to close the window.

> *If you see a security warning, open PowerShell as Administrator (right-click PowerShell, choose "Run as Administrator") and run:*
>
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```
>
> Then try right-clicking the script again.

### install-claude-skills.sh (macOS)

Save this as `install-claude-skills.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

GITHUB_DIR="$HOME/Documents/Github"
mkdir -p "$GITHUB_DIR"
cd "$GITHUB_DIR"

echo "Installing /make-it skill..."
if [ -d "make-it" ]; then
    cd make-it && git pull && ./install.sh && cd ..
else
    git clone https://github.com/SleepNumberInc/make-it.git
    cd make-it && ./install.sh && cd ..
fi

echo ""
echo "Installing /ship-it skill..."
if [ -d "ship-it" ]; then
    cd ship-it && git pull && ./install.sh && cd ..
else
    git clone https://github.com/SleepNumberInc/ship-it.git
    cd ship-it && ./install.sh && cd ..
fi

echo ""
echo "==============================="
echo "  Installation Complete."
echo "==============================="
echo ""
echo "Close Claude Code and reopen it."
echo "Then type /make-it or /ship-it to get started."
```

### install-claude-skills.ps1 (Windows)

Save this as `install-claude-skills.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$GithubDir = Join-Path $HOME "Documents\Github"
New-Item -ItemType Directory -Force -Path $GithubDir | Out-Null
Set-Location $GithubDir

Write-Host "Installing /make-it skill..." -ForegroundColor Cyan
if (Test-Path "make-it") {
    Set-Location make-it
    git pull
    bash ./install.sh
    Set-Location ..
} else {
    git clone https://github.com/SleepNumberInc/make-it.git
    Set-Location make-it
    bash ./install.sh
    Set-Location ..
}

Write-Host ""
Write-Host "Installing /ship-it skill..." -ForegroundColor Cyan
if (Test-Path "ship-it") {
    Set-Location ship-it
    git pull
    bash ./install.sh
    Set-Location ..
} else {
    git clone https://github.com/SleepNumberInc/ship-it.git
    Set-Location ship-it
    bash ./install.sh
    Set-Location ..
}

Write-Host ""
Write-Host "===============================" -ForegroundColor Green
Write-Host "  Installation Complete." -ForegroundColor Green
Write-Host "===============================" -ForegroundColor Green
Write-Host ""
Write-Host "Close Claude Code and reopen it."
Write-Host "Then type /make-it or /ship-it to get started."
Write-Host ""
Read-Host "Press Enter to close"
```

---

## Troubleshooting

| Problem | Platform | Solution |
|---------|----------|----------|
| "git: command not found" | macOS | Open Terminal, type `xcode-select --install`, click "Install" in the popup. Try again after it finishes. |
| "git is not recognized" | Windows | Download and install Git from https://git-scm.com/download/win, then close and reopen PowerShell. |
| "bash is not recognized" | Windows | Try the automated script (`install-claude-skills.ps1`) instead -- it handles this for you. |
| "Permission denied" | macOS | Run `chmod +x install.sh` (or `chmod +x install-claude-skills.sh` for the automated script), then try again. |
| "Permission denied" | Windows | Right-click PowerShell, choose "Run as Administrator", then try again. |
| Skill doesn't appear in Claude | Both | Close Claude Code completely and reopen it. Skills only load at startup. |
| "repository not found" or "access denied" | Both | Make sure you are on VPN and have access to the SleepNumberInc GitHub organization. |
