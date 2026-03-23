# Windows Setup Guide for Claude Code + /make-it

This guide walks you through setting up Claude Code and /make-it skills on a Windows computer, step by step. No technical experience required -- just follow each step in order.

---

## Before You Start

- You will need **administrator access** on your computer for some steps (the guide tells you when)
- Some steps require you to **close and reopen PowerShell** -- this is how Windows picks up newly installed programs
- The entire setup takes about 20-30 minutes, depending on your internet speed
- **You must restart your computer once** during this process (after Docker Desktop)

---

## How to Open PowerShell

You will use PowerShell for every step in this guide.

1. Click the **Start** button (or press the Windows key)
2. Type **PowerShell**
3. Click **Windows PowerShell**

> **When a step says "Open PowerShell as Administrator":** Right-click **Windows PowerShell** and choose **Run as administrator**, then click **Yes** when prompted.

---

## Important: Run This First in Every PowerShell Window

Every time you open a new PowerShell window during this guide, **run this command first**:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

This allows PowerShell to run the scripts needed for installation. It only affects the current window -- it resets when you close it. You do not need administrator access for this command.

> **Why?** Windows blocks scripts by default as a security measure. This temporarily allows them for just this window.

---

## Step 1: Install Node.js

Node.js is the runtime that Claude Code needs to run.

Open PowerShell and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install OpenJS.NodeJS.LTS
```

When it finishes, **close PowerShell and open a new PowerShell window**, then verify it worked:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
node --version
npm --version
```

You should see version numbers (e.g., `v22.x.x` and `10.x.x`). If you see an error instead, try closing and reopening PowerShell one more time.

> **If `winget` is not available** (older Windows 10): Open a browser, go to https://nodejs.org, download the **LTS** installer, and run it. Accept all defaults.

---

## Step 2: Install Git for Windows

Git is version control software. Claude Code also needs the "git-bash" shell that comes with it.

In PowerShell:

```powershell
winget install Git.Git
```

**Close PowerShell and open a new PowerShell window**, then verify:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
git --version
```

You should see something like `git version 2.x.x`.

### Find where bash.exe was installed

Claude Code needs to know where git-bash is on your computer. Run this:

```powershell
Get-Command git | Select-Object -ExpandProperty Source
```

You will see a path like one of these:

```
C:\Users\YourName\AppData\Local\Programs\Git\cmd\git.exe
C:\Program Files\Git\cmd\git.exe
```

Take that path and replace `\cmd\git.exe` at the end with `\bin\bash.exe`. For example:

- If you got `C:\Users\YourName\AppData\Local\Programs\Git\cmd\git.exe`
  - Your bash path is: `C:\Users\YourName\AppData\Local\Programs\Git\bin\bash.exe`
- If you got `C:\Program Files\Git\cmd\git.exe`
  - Your bash path is: `C:\Program Files\Git\bin\bash.exe`

### Tell Claude Code where bash.exe is

Run this command, replacing the path with **your actual bash.exe path** from above:

```powershell
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "C:\Users\YourName\AppData\Local\Programs\Git\bin\bash.exe", "User")
```

**Close PowerShell and open a new PowerShell window** for this to take effect.

---

## Step 3: Install Azure CLI

Azure CLI lets your computer talk to Azure AI Foundry (the AI service that powers Claude Code in your organization).

In PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install Microsoft.AzureCLI
```

**Close PowerShell and open a new PowerShell window**, then log in to Azure:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az login
```

A browser window will open. **Sign in with your corporate/work account** (the same one you use for email and Teams).

After signing in, go back to PowerShell and verify it worked:

```powershell
az account show --query name -o tsv
```

You should see your organization's Azure subscription name.

---

## Step 4: Install Docker Desktop

Docker runs your apps in isolated containers on your computer. **This step requires administrator access and a restart.**

In PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install Docker.DockerDesktop
```

**Restart your computer** after installation (Docker requires this).

After restarting:

1. Open **Docker Desktop** from the Start menu
2. Wait for it to finish starting (you will see "Docker Desktop is running" in the system tray near the clock)
3. If it asks you to accept a license agreement, click **Accept**

Open a new PowerShell window and verify:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
docker --version
docker compose version
```

You should see version numbers for both commands.

> **If you see errors about WSL 2:** Open **PowerShell as Administrator** and run:
> ```powershell
> wsl --install
> ```
> Then restart your computer again.

---

## Step 5: Install Claude Code

In PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
npm install -g @anthropic-ai/claude-code
```

Verify:

```powershell
claude --version
```

---

## Step 6: Configure Claude Code for Azure AI Foundry

Claude Code needs two configuration files to connect to your organization's AI service. You will create both files in this step.

### Find your Windows username

Run this in PowerShell and write down the result -- you will need it below:

```powershell
$env:USERNAME
```

This prints something like `BARKNX` or `jsmith`. In all examples below, replace `YourName` with **your actual username**.

### Create the token helper script

This script gets a security token so Claude Code can talk to Azure AI Foundry.

1. Open **File Explorer**
2. Navigate to `C:\Users\YourName\.claude\` (replace `YourName` with your username)
   - If the `.claude` folder does not exist, create it
3. Create a new file called `get-claude-token.ps1`
4. Open it in Notepad and paste this content:

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

5. Save the file

> **Tip:** If Notepad adds `.txt` to the filename (making it `get-claude-token.ps1.txt`), rename it to remove the `.txt` extension. In File Explorer, make sure "File name extensions" is checked under the **View** tab so you can see the full filename.

### Create the settings file

1. In the same `.claude` folder, create a new file called `settings.json`
2. Open it in Notepad and paste this content, **replacing `YourName` with your actual username**:

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

3. Save the file

**Double-check:** The `apiKeyHelper` line must have your real username and use double backslashes (`\\`). For example, if your username is `BARKNX`, the line should read:

```
"apiKeyHelper": "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\BARKNX\\.claude\\get-claude-token.ps1",
```

---

## Step 7: Install /make-it Skills

In PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```

You should see a list of installed skills when it finishes.

**Alternative** -- if you prefer to clone the repository first:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
git clone https://github.com/sealmindset/make-it.git
cd make-it
.\install.ps1
```

---

## Step 8: Verify Everything Works

**Close PowerShell and open a new PowerShell window**, then:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

# Log in to Azure (you need to do this each time you open a new PowerShell window)
az login
```

A browser window will open. Sign in with your corporate account. Then go back to PowerShell:

```powershell
# Verify the token works (should print a long string of letters and numbers)
az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv

# Go to your projects folder (create it first if it doesn't exist)
mkdir ~\Documents\GitHub -ErrorAction SilentlyContinue
cd ~\Documents\GitHub

# Start Claude Code
claude
```

Inside Claude Code, type `/make-it` -- you should see the skill activate and greet you.

**Congratulations -- you are all set!**

---

## Optional: Install GitHub CLI

GitHub CLI lets you push your code to GitHub and create pull requests from the terminal.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install GitHub.cli
```

**Close PowerShell and open a new PowerShell window**, then authenticate:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
gh auth login
```

Follow the prompts to authenticate with your GitHub account.

---

## Optional: Install VS Code

VS Code is a code editor. Not required, but helpful if you ever want to look at the generated code.

```powershell
winget install Microsoft.VisualStudioCode
```

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

## Troubleshooting

### "Running scripts is disabled on this system" or "execution policy" errors

You forgot to run the execution policy command. Run this first:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Then retry the command that failed. You need to do this every time you open a new PowerShell window.

### "claude is not recognized"

Node.js is not installed or not in your PATH.

1. Close and reopen PowerShell
2. Run `Set-ExecutionPolicy -Scope Process Bypass`
3. Try `node --version` -- if this also fails, reinstall Node.js (Step 1)

### "Claude Code was unable to find CLAUDE_CODE_GIT_BASH_PATH"

The path you set does not match where bash.exe actually is on your computer.

1. Find the real path:

```powershell
Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)", "$env:LOCALAPPDATA\Programs" -Recurse -Filter "bash.exe" -ErrorAction SilentlyContinue | Select-Object FullName
```

2. Look for a result containing `\Git\bin\bash.exe` (ignore any `\WinSxS\` results -- those are something else)
3. Set the correct path:

```powershell
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "paste-your-actual-path-here", "User")
```

4. Close and reopen PowerShell

### "401 Azure AD JWT not present"

This means Claude Code could not get a valid security token from Azure. Work through these checks in order:

**Check 1: Are you logged in to Azure?**

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az login
az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
```

The second command should print a long string of letters and numbers (the token). If it shows an error instead, your account may not have access to Azure Cognitive Services -- contact your Azure administrator.

**Check 2: Does your settings.json have your real username?**

```powershell
$env:USERNAME
Get-Content "$env:USERPROFILE\.claude\settings.json"
```

Compare the username printed by the first command with what is in the `apiKeyHelper` line. They must match. If you see `YourName` instead of your actual username, edit the file and fix it.

**Check 3: Does the token script file exist?**

```powershell
Test-Path "$env:USERPROFILE\.claude\get-claude-token.ps1"
```

If this prints `False`, go back to Step 6 and create the file.

**Check 4: Does the token script work on its own?**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\get-claude-token.ps1"
```

This should print ONLY a long token string -- nothing else. If you see warnings, errors, or extra text mixed in, replace the contents of `get-claude-token.ps1` with this version:

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

**Check 5: Restart Claude Code**

After fixing any of the above, close Claude Code completely, then in PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az login
claude
```

### Docker errors

Make sure Docker Desktop is running -- look for the whale icon in the system tray (near the clock at the bottom right of your screen).

If Docker Desktop won't start or shows WSL errors:

1. Open **PowerShell as Administrator** (right-click, Run as administrator)
2. Run:

```powershell
wsl --install
```

3. Restart your computer

### install.ps1 fails with "Join-Path" errors

You have an older version of the install script. Use the one-line installer which always gets the latest:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```
