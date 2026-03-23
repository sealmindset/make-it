# Windows Setup Guide for Claude Code + /make-it

This guide gets Claude Code and /make-it skills running on your Windows computer. No technical experience required.

---

## Automated Setup (Recommended)

The install script handles everything: Node.js, Git, Azure CLI, Docker, Claude Code, and all configuration. If it needs to restart your computer (for Docker), it saves progress and picks up where it left off.

### First Run

1. Click the **Start** button, type **PowerShell**, and click **Windows PowerShell**
2. Copy and paste these two commands, pressing Enter after each:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```

3. Follow the on-screen prompts
4. When asked to log in to Azure, a browser opens -- **sign in with your corporate/work account** (the same one you use for email and Teams)

### If the Script Says "Restart Required"

Docker Desktop needs a restart to finish installing. Here is what to do:

1. Restart your computer
2. After restarting, open **Docker Desktop** from the Start menu and wait for it to say "Docker Desktop is running" (look near the clock for a whale icon)
3. Open **PowerShell** again
4. Run the same two commands:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```

The script picks up where it left off -- it does not reinstall things that are already done.

### When It Finishes

The script shows a verification checklist and your daily workflow instructions. You are ready to go.

---

## Your Daily Workflow

Every time you want to use Claude Code, open PowerShell and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az login
cd ~\Documents\GitHub
claude
```

Inside Claude Code:

```
/make-it          Build a new app from scratch
/try-it           Test your app in the browser
/resume-it        Continue working on your app
/retrofit-it      Upgrade an existing app
/make-it update   Update to the latest version of the skills
```

> **Note:** Azure login tokens expire after about 1-2 hours. If Claude Code suddenly stops responding or shows errors, close it, run `az login` again in PowerShell, and restart `claude`.

---

## Manual Setup (If You Prefer Step-by-Step)

If you prefer to install each piece yourself instead of using the automated script, follow these steps in order.

### Before You Start

- You will need **administrator access** on your computer for Docker Desktop and WSL
- The entire setup takes about 20-30 minutes
- **You must restart your computer once** (after Docker Desktop)
- Every time you open a new PowerShell window, **run this command first**:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

> **Why?** Windows blocks scripts by default. This temporarily allows them for just this window.

### How to Open PowerShell

1. Click the **Start** button (or press the Windows key)
2. Type **PowerShell**
3. Click **Windows PowerShell**

> **When a step says "Open PowerShell as Administrator":** Right-click **Windows PowerShell** and choose **Run as administrator**, then click **Yes** when prompted.

### Step 1: Install Node.js

Node.js is the runtime that Claude Code needs to run.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install OpenJS.NodeJS.LTS
```

**Close PowerShell and open a new one**, then verify:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
node --version
npm --version
```

You should see version numbers (e.g., `v22.x.x` and `10.x.x`).

> **If `winget` is not available** (older Windows 10): Open a browser, go to https://nodejs.org, download the **LTS** installer, and run it. Accept all defaults.

### Step 2: Install Git for Windows

Git is version control software. Claude Code also needs the "git-bash" shell that comes with it.

```powershell
winget install Git.Git
```

**Close PowerShell and open a new one**, then verify:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
git --version
```

#### Find where bash.exe was installed

```powershell
Get-Command git | Select-Object -ExpandProperty Source
```

You will see a path like:

```
C:\Users\YourName\AppData\Local\Programs\Git\cmd\git.exe
```

Take that path and replace `\cmd\git.exe` at the end with `\bin\bash.exe`:

```
C:\Users\YourName\AppData\Local\Programs\Git\bin\bash.exe
```

#### Tell Claude Code where bash.exe is

Replace the path below with **your actual bash.exe path**:

```powershell
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "C:\Users\YourName\AppData\Local\Programs\Git\bin\bash.exe", "User")
```

**Close PowerShell and open a new one** for this to take effect.

### Step 3: Install Azure CLI

Azure CLI lets your computer talk to Azure AI Foundry (the AI service that powers Claude Code in your organization).

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install Microsoft.AzureCLI
```

**Close PowerShell and open a new one**, then log in:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az login
```

A browser window will open. **Sign in with your corporate/work account.** Then verify:

```powershell
az account show --query name -o tsv
```

### Step 4: Install Docker Desktop

Docker runs your apps in isolated containers. **This step requires a restart.**

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install Docker.DockerDesktop
```

**Restart your computer.** After restarting:

1. Open **Docker Desktop** from the Start menu
2. Wait for it to say "Docker Desktop is running" (whale icon near the clock)
3. If asked to accept a license agreement, click **Accept**

Open PowerShell and verify:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
docker --version
docker compose version
```

> **If you see errors about WSL 2:** Open **PowerShell as Administrator** and run `wsl --install`, then restart your computer again.

### Step 5: Install Claude Code

```powershell
Set-ExecutionPolicy -Scope Process Bypass
npm install -g @anthropic-ai/claude-code
```

Verify:

```powershell
claude --version
```

### Step 6: Configure Claude Code for Azure AI Foundry

Claude Code needs two configuration files. First, find your Windows username:

```powershell
$env:USERNAME
```

Replace `YourName` in the steps below with the value this prints.

#### Create the token helper script

Create `C:\Users\YourName\.claude\get-claude-token.ps1` with this content:

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

> **Tip:** If Notepad adds `.txt` to the filename, rename it to remove the `.txt`. In File Explorer, check "File name extensions" under the **View** tab.

#### Create the settings file

Create `C:\Users\YourName\.claude\settings.json` with this content (**replace `YourName` with your actual username**):

```json
{
  "apiKeyHelper": "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\YourName\\.claude\\get-claude-token.ps1",
  "env": {
    "CLAUDE_CODE_USE_FOUNDRY": "1",
    "ANTHROPIC_FOUNDRY_BASE_URL": "https://snapistg-scus.azure.sleepnumber.com/anthropic",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "cogdep-aifoundry-dev-eus2-claude-sonnet-4-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "cogdep-aifoundry-dev-eus2-claude-haiku-4-5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "cogdep-aifoundry-dev-eus2-claude-opus-4-6"
  }
}
```

**Double-check:** The `apiKeyHelper` line must have your real username with double backslashes (`\\`).

### Step 7: Install /make-it Skills

```powershell
Set-ExecutionPolicy -Scope Process Bypass
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```

### Step 8: Verify Everything Works

**Close PowerShell and open a new one:**

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az login
cd ~\Documents\GitHub
claude
```

Inside Claude Code, type `/make-it` -- you should see the skill activate.

---

## Optional Tools

### GitHub CLI

Push code and create pull requests from the terminal:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install GitHub.cli
```

**Close PowerShell and open a new one**, then authenticate:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
gh auth login
```

### VS Code

Code editor (not required, but helpful for browsing generated code):

```powershell
winget install Microsoft.VisualStudioCode
```

---

## Troubleshooting

### "Running scripts is disabled on this system"

Run this first in every new PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

### "claude is not recognized"

Node.js is not installed or not in your PATH.

1. Close and reopen PowerShell
2. Run `Set-ExecutionPolicy -Scope Process Bypass`
3. Try `node --version` -- if this also fails, reinstall Node.js (Step 1)

### "Claude Code was unable to find CLAUDE_CODE_GIT_BASH_PATH"

The path does not match where bash.exe actually is. Find the real path:

```powershell
Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)", "$env:LOCALAPPDATA\Programs" -Recurse -Filter "bash.exe" -ErrorAction SilentlyContinue | Select-Object FullName
```

Look for a result containing `\Git\bin\bash.exe` (ignore `\WinSxS\` results -- those are something else). Then set it:

```powershell
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "paste-your-actual-path-here", "User")
```

Close and reopen PowerShell.

### "401 Azure AD JWT not present"

Claude Code could not get a valid security token. Work through these checks:

**Check 1: Are you logged in to Azure?**

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az login
az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
```

The second command should print a long string. If it shows an error, your account may not have Cognitive Services access -- contact your Azure administrator.

**Check 2: Does settings.json have your real username?**

```powershell
$env:USERNAME
Get-Content "$env:USERPROFILE\.claude\settings.json"
```

The `apiKeyHelper` path must contain your real username, not the `YourName` placeholder.

**Check 3: Does the token script exist?**

```powershell
Test-Path "$env:USERPROFILE\.claude\get-claude-token.ps1"
```

If `False`, go back to Step 6 and create it.

**Check 4: Does the token script work on its own?**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\get-claude-token.ps1"
```

Should print ONLY a long token string -- no warnings or extra text.

**Check 5: Restart Claude Code**

Close Claude Code, run `az login`, then start `claude` again.

### Docker errors

Make sure Docker Desktop is running (whale icon near the clock). If it shows WSL errors:

1. Open **PowerShell as Administrator**
2. Run `wsl --install`
3. Restart your computer
