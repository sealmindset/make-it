# Windows Setup Guide for Claude Code + /make-it

Complete instructions to install and run Claude Code with /make-it skills on Windows.

---

## Prerequisites

You need four things installed before Claude Code will work on Windows:

| # | Tool | Purpose |
|---|------|---------|
| 1 | **Node.js (LTS)** | Runtime for Claude Code |
| 2 | **Git for Windows** | Version control + provides git-bash (required by Claude Code) |
| 3 | **Azure CLI** | Authentication to Azure AI Foundry (enterprise AI backend) |
| 4 | **Docker Desktop** | Runs your apps locally in containers |

Optional but recommended:

| Tool | Purpose |
|------|---------|
| **GitHub CLI** | Push code and create pull requests from the terminal |
| **VS Code** | Code editor |

---

## Step 1: Install Node.js

Open PowerShell and run:

```powershell
winget install OpenJS.NodeJS.LTS
```

**Close and reopen PowerShell**, then verify:

```powershell
node --version
npm --version
```

You should see version numbers (e.g., `v22.x.x` and `10.x.x`).

> **If `winget` is not available** (older Windows 10), download the LTS installer from https://nodejs.org and run it manually.

---

## Step 2: Install Git for Windows

```powershell
winget install Git.Git
```

**Close and reopen PowerShell**, then verify:

```powershell
git --version
```

### Find your bash.exe path

Claude Code requires git-bash. Find where it was installed:

```powershell
Get-Command git | Select-Object -ExpandProperty Source
```

This shows something like:

```
C:\Users\YourName\AppData\Local\Programs\Git\cmd\git.exe
```

Replace `\cmd\git.exe` with `\bin\bash.exe` to get the bash path. For example:

```
C:\Users\YourName\AppData\Local\Programs\Git\bin\bash.exe
```

If you're not sure, search for it:

```powershell
Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)", "$env:LOCALAPPDATA\Programs" -Recurse -Filter "bash.exe" -ErrorAction SilentlyContinue | Select-Object FullName
```

Look for a path containing `\Git\bin\bash.exe` (not `\WinSxS\` -- those are WSL, not git-bash).

### Set the environment variable

Replace the path below with **your actual bash.exe path** from the previous step:

```powershell
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "C:\Users\YourName\AppData\Local\Programs\Git\bin\bash.exe", "User")
```

**Close and reopen PowerShell** for this to take effect.

> **Common paths** (check which one exists on your machine):
> - `C:\Users\YourName\AppData\Local\Programs\Git\bin\bash.exe` (user install)
> - `C:\Program Files\Git\bin\bash.exe` (system install)

---

## Step 3: Install Azure CLI

```powershell
winget install Microsoft.AzureCLI
```

**Close and reopen PowerShell**, then log in:

```powershell
az login
```

This opens a browser window. Sign in with your corporate account.

Verify:

```powershell
az account show --query name -o tsv
```

---

## Step 4: Install Docker Desktop

```powershell
winget install Docker.DockerDesktop
```

After installation, **restart your computer** (Docker requires a reboot). Then open Docker Desktop from the Start menu and wait for it to finish starting.

Verify:

```powershell
docker --version
docker compose version
```

> **Note:** If you see errors about WSL 2, run `wsl --install` in an elevated PowerShell and restart.

---

## Step 5: Install Claude Code

```powershell
npm install -g @anthropic-ai/claude-code
```

Verify:

```powershell
claude --version
```

---

## Step 6: Configure Claude Code for Azure AI Foundry

Claude Code needs to authenticate against Azure AI Foundry. This requires two files in your `.claude` directory.

### Find your username

You'll need your Windows username for the file paths below. Run this in PowerShell:

```powershell
$env:USERNAME
```

In all examples below, replace `YourName` with this value.

### Create the token helper script

Create the file `C:\Users\YourName\.claude\get-claude-token.ps1` with this content:

```powershell
# Check if already logged in to Azure CLI
$null = az account get-access-token 2>$null
if ($LASTEXITCODE -ne 0) {
    # Not logged in, so login
    az login | Out-Null
}

# Get access token for Azure Cognitive Services
az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
```

### Create the settings file

Create or edit `C:\Users\YourName\.claude\settings.json`:

```json
{
  "apiKeyHelper": "powershell -ExecutionPolicy Bypass -File C:\\Users\\YourName\\.claude\\get-claude-token.ps1",
  "env": {
    "CLAUDE_CODE_USE_FOUNDRY": "1",
    "ANTHROPIC_FOUNDRY_BASE_URL": "https://snapistg-scus.azure.sleepnumber.com/anthropic",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "cogdep-aifoundry-dev-eus2-claude-sonnet-4-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "cogdep-aifoundry-dev-eus2-claude-haiku-4-5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "cogdep-aifoundry-dev-eus2-claude-opus-4-6"
  }
}
```

**Important:** Replace `YourName` with your actual Windows username in both the script path and the `apiKeyHelper` value. Use double backslashes (`\\`) in the JSON file.

---

## Step 7: Install /make-it Skills

### Option A: One-line install (no clone needed)

```powershell
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```

### Option B: Clone and install

```powershell
git clone https://github.com/sealmindset/make-it.git
cd make-it
.\install.ps1
```

---

## Step 8: Verify Everything Works

**Close and reopen PowerShell**, then:

```powershell
# 1. Log in to Azure (required EVERY time you open a new PowerShell session,
#    or whenever your token expires -- typically every 1-2 hours)
az login

# 2. Verify the token works
az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv

# 3. Start Claude Code
cd ~\Documents\GitHub
claude
```

Inside Claude Code, type `/make-it` -- you should see the skill activate.

> **Important:** You must run `az login` before starting Claude Code each session. The token helper script retrieves your existing token -- it cannot open a browser to log you in.

---

## Optional: Install GitHub CLI

```powershell
winget install GitHub.cli
```

**Close and reopen PowerShell**, then authenticate:

```powershell
gh auth login
```

Follow the prompts to authenticate with your GitHub account.

---

## Optional: Install VS Code

```powershell
winget install Microsoft.VisualStudioCode
```

---

## Troubleshooting

### "claude is not recognized"

Node.js isn't in your PATH. Close and reopen PowerShell. If that doesn't work, verify Node.js is installed:

```powershell
node --version
```

If `node` also isn't found, reinstall Node.js and make sure "Add to PATH" is checked during installation.

### "Claude Code was unable to find CLAUDE_CODE_GIT_BASH_PATH"

The path in your environment variable doesn't match where bash.exe actually is. Find the real path:

```powershell
Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)", "$env:LOCALAPPDATA\Programs" -Recurse -Filter "bash.exe" -ErrorAction SilentlyContinue | Select-Object FullName
```

Look for a result containing `\Git\bin\bash.exe` and update the environment variable:

```powershell
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "<actual path>", "User")
```

Then close and reopen PowerShell.

### "bash.exe found but only WinSxS paths"

Those are WSL (Windows Subsystem for Linux), not git-bash. You need to install Git for Windows:

```powershell
winget install Git.Git
```

### "401 Azure AD JWT not present"

This means Claude Code couldn't get a valid Azure token. Work through these checks in order:

**Check 1: Are you logged in to Azure?**

```powershell
az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
```

If this fails or prints an error, log in first:

```powershell
az login
```

Then retry the token command. It should print a long string (the token).

**Check 2: Does your settings.json have your actual username?**

```powershell
$env:USERNAME
Get-Content "$env:USERPROFILE\.claude\settings.json"
```

The `apiKeyHelper` path must contain your real username, not the literal `YourName` placeholder. The path must use double backslashes (`\\`).

**Check 3: Does the token script exist at the path in settings.json?**

```powershell
Test-Path "$env:USERPROFILE\.claude\get-claude-token.ps1"
```

If `False`, create the script (see [Step 6](#step-6-configure-claude-code-for-azure-ai-foundry)).

**Check 4: Does the token script run cleanly?**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\get-claude-token.ps1"
```

This should print ONLY a token string -- no warnings, no extra text. If you see extra output (Azure CLI warnings, profile messages, etc.), that corrupts the token. Replace your `get-claude-token.ps1` with this hardened version:

```powershell
$ErrorActionPreference = "Stop"
try {
    $token = (az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv) 2>$null
    if (-not $token) { throw "empty token" }
    [Console]::Out.Write($token.Trim())
} catch {
    [Console]::Error.WriteLine("ERROR: Run 'az login' before starting Claude Code.")
    exit 1
}
```

And update `settings.json` to use `-NoProfile` (prevents PowerShell profile from printing extra output):

```json
{
  "apiKeyHelper": "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\YourName\\.claude\\get-claude-token.ps1",
  ...
}
```

**Check 5: Restart Claude Code**

After fixing any of the above, close Claude Code completely and reopen it:

```powershell
claude
```

> **Token expiry:** Azure tokens expire after ~1-2 hours. If Claude Code suddenly stops working mid-session, exit, run `az login` again, and restart.

### Docker errors

Make sure Docker Desktop is running (check the system tray). If you see WSL errors:

```powershell
wsl --install
```

Restart your computer after installing WSL.

### PowerShell execution policy errors

If scripts are blocked by execution policy:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### install.ps1 fails with "Join-Path" errors

You're running an older version of the install script. Pull the latest:

```powershell
git pull
.\install.ps1
```

Or use the one-line installer which always gets the latest version:

```powershell
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```

---

## Quick Reference

Once everything is installed, your day-to-day workflow is:

```powershell
az login                # Always first -- authenticate to Azure
cd ~\Documents\GitHub
claude                  # Start Claude Code
> /make-it              # Build a new app
> /try-it               # Test your app in the browser
> /resume-it            # Continue working on your app
> /retrofit-it          # Upgrade an existing app
```

To update the skills later:

```
> /make-it update
```
