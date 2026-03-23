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

### Create the token helper script

Create the file `C:\Users\YourName\.claude\get-claude-token.ps1` with this content:

```powershell
# Get access token for Azure Cognitive Services
# IMPORTANT: You must run "az login" BEFORE starting Claude Code.
# This script cannot open a browser interactively -- it only retrieves
# a token from an existing Azure CLI session.

$token = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Azure CLI not logged in. Run 'az login' in PowerShell before starting Claude Code."
    exit 1
}

Write-Output $token
```

> **Why no `az login` in the script?** Claude Code calls this script in a background subprocess that cannot open a browser window. You must log in to Azure CLI yourself before launching Claude Code.

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

This means Claude Code couldn't get a valid Azure token. The most common cause: you didn't run `az login` before starting Claude Code.

**Fix:** Exit Claude Code, then:

```powershell
# 1. Log in to Azure
az login

# 2. Verify the token works (should print a long string)
az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv

# 3. Restart Claude Code
claude
```

If the token command fails, your account may not have access to Azure Cognitive Services. Contact your Azure administrator.

> **Token expiry:** Azure tokens expire after ~1-2 hours. If Claude Code suddenly stops working mid-session, exit Claude Code, run `az login` again, and restart.

### Other authentication errors

Verify your `settings.json` has the correct username in the `apiKeyHelper` path:

```powershell
# Check your actual username
$env:USERNAME

# The path in settings.json must match
Get-Content "$env:USERPROFILE\.claude\settings.json"
```

Make sure the path to `get-claude-token.ps1` uses double backslashes (`\\`) in the JSON file.

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
