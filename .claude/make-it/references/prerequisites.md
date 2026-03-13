# Prerequisites Reference

These prerequisites MUST be satisfied before /make-it can build anything. The skill checks what it can automatically and guides the user through anything missing.

This is Phase 0 -- it runs BEFORE ideation begins.

---

## Universal Prerequisites

These are required for everyone, regardless of environment.

### 1. Git

**Why needed:** Version control for all code.
**How to check:** `git --version 2>/dev/null`
**If missing:**
- macOS: Pre-installed on most systems. If not: `xcode-select --install`
- Windows: Download from https://git-scm.com/download/win
- Linux: `sudo apt install git` or `sudo yum install git`

### 2. Docker / Container Runtime

**Why needed:** Creates consistent, isolated local development environments that mirror production. Containers are ephemeral sandboxes -- safe for non-technical users to experiment without risk to their machine or network.

**Recommended options:**
- **Docker Desktop:** Industry standard, easy setup. Free for personal use, small businesses, education. Requires license for larger enterprises.
- **Rancher Desktop:** Free, open-source alternative with no licensing restrictions. Provides the same `docker` and `docker compose` CLI.

**How to check:** `docker --version 2>/dev/null`

**If missing (macOS):**
```bash
# Option 1: Docker Desktop
# Download from https://www.docker.com/products/docker-desktop

# Option 2: Rancher Desktop
brew install --cask rancher

# Restart Terminal after installation
```

**If missing (Windows):**
```powershell
# Option 1: Docker Desktop
# Download from https://www.docker.com/products/docker-desktop

# Option 2: Rancher Desktop
# Download from https://rancherdesktop.io

# Restart Terminal after installation
# Note: Rancher Desktop manages its own WSL integration automatically
```

**If missing (Linux):**
```bash
# Follow official Docker installation guide for your distribution
# https://docs.docker.com/engine/install/
```

### 3. GitHub CLI (gh)

**Why needed:** Required by /ship-it for creating branches, PRs, and deployment. Also enables automatic repository setup and authentication.

**How to check:** `gh --version 2>/dev/null`

**If missing:**
- macOS: `brew install gh`
- Windows: `winget install --id GitHub.cli` or `choco install gh`
- Linux: See https://github.com/cli/cli/blob/trunk/docs/install_linux.md

**After installation:** Run `gh auth login` to authenticate with GitHub

### 4. Claude Code

**Why needed:** This IS the development environment.
**How to check:** Already running if they're using /make-it
**If missing:** Visit https://claude.ai/download to install

### 5. Visual Studio Code (IDE)

**Why needed:** Code editor for viewing and optionally editing generated code.
**How to check:** `code --version 2>/dev/null`
**If missing:**
- macOS: `brew install --cask visual-studio-code` or download from https://code.visualstudio.com
- Windows: `winget install --id Microsoft.VisualStudioCode` or download from https://code.visualstudio.com
- Linux: Download from https://code.visualstudio.com or use your distribution's package manager

---

## Enterprise Prerequisites (Optional)

These apply only if you work in a corporate environment with specific access controls. Most individual developers and small teams can skip this section.

### 1. VPN Access

**Why needed:** Some organizations require VPN connection to access development services like internal GitHub Enterprise, cloud providers, or authentication systems.

**How to check:** Ask the user: "Does your organization require you to be connected to VPN for development work?"

**If needed but missing:**
- Contact your IT department or help desk
- Common VPN solutions: Cisco AnyConnect, Palo Alto GlobalProtect, FortiClient, Pulse Secure
- Typically requires approval from IT security or network operations

### 2. Local Admin Rights

**Why needed:** Some organizations restrict software installation. You may need elevated privileges to install Docker, programming language runtimes, or other development tools.

**How to check:**
- macOS/Linux: `groups $(whoami) 2>/dev/null | grep -q admin && echo "yes" || echo "no"`
- Windows: Check if you're in the local Administrators group

**If needed but missing:**
- Contact your IT department or help desk
- Request temporary or permanent local admin access
- Justification: "Required to install development tools (Docker, SDKs, etc.)"
- Note: Some organizations provide time-limited admin access that must be renewed periodically

### 3. SSL-Inspecting Proxy Bypass

**Why needed:** Corporate networks sometimes use SSL-inspecting proxies (Zscaler, Netskope, Palo Alto GlobalProtect, etc.) that interfere with Docker builds and package downloads by intercepting HTTPS traffic. This causes TLS/certificate errors during builds.

**How to check:** If Docker builds fail with certificate or TLS errors, an SSL-inspecting proxy is likely the cause.

**Common symptoms:**
- `certificate verify failed` errors during `docker compose build`
- `SSL: CERTIFICATE_VERIFY_FAILED` when downloading packages
- `x509: certificate signed by unknown authority` errors

**If needed:**
- Ask your IT team about "developer bypass" or "developer exclusion" options
- Some organizations provide special groups/permissions that allow temporary proxy disablement
- Alternative: Add corporate root certificates to Docker and development tools (IT can provide guidance)
- Note: Only disable the proxy when actively building. Re-enable for normal work.

### 4. Cloud Provider Access

**Why needed:** Only required if you plan to deploy your application to a cloud provider. Local development works without cloud access.

**How to check (only check the provider you're using):**
- Azure: `az account show 2>/dev/null`
- AWS: `aws sts get-caller-identity 2>/dev/null`
- Google Cloud: `gcloud auth list 2>/dev/null`

**If needed but missing:**
- **Azure:**
  - Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
  - Run `az login` to authenticate
  - Enterprise users: Contact your cloud team for subscription access

- **AWS:**
  - Install AWS CLI: https://aws.amazon.com/cli/
  - Run `aws configure` to set up credentials
  - Enterprise users: Contact your cloud team for IAM credentials

- **Google Cloud:**
  - Install gcloud CLI: https://cloud.google.com/sdk/docs/install
  - Run `gcloud auth login` to authenticate
  - Enterprise users: Contact your cloud team for project access

### 5. Organization GitHub Access

**Why needed:** Some organizations use GitHub Enterprise or require membership in specific GitHub teams/organizations before you can create repositories or push code.

**How to check:** `gh auth status 2>/dev/null`

**If the check passes but you can't create repos:**
- You may need to be added to your organization's GitHub organization
- Contact your engineering leads or IT team
- Provide your GitHub username and request access to the appropriate team/organization

---

## Preflight Check Order

The skill should check prerequisites in this order (fast automated checks first, then environment detection):

### 1. Instant checks (automated)

Run these checks automatically without asking the user:
- Git installed? `git --version 2>/dev/null`
- Docker installed? `docker --version 2>/dev/null`
- GitHub CLI installed and authenticated? `gh auth status 2>/dev/null`
- Claude Code running? (implicit -- they're here)
- VS Code installed? `code --version 2>/dev/null`

### 2. Cloud CLI check (conditional)

Only check if the user has mentioned a cloud provider or if deploying:
- Azure: `az account show 2>/dev/null`
- AWS: `aws sts get-caller-identity 2>/dev/null`
- Google Cloud: `gcloud auth list 2>/dev/null`

### 3. Enterprise environment detection

Look for signals that the user is in a corporate environment:
- VPN client installed (Cisco AnyConnect, GlobalProtect, etc.)
- Corporate domain in git config (`git config user.email`)
- SSL-inspecting proxy detected (check for corporate certificates)

If detected, ask:
- "I noticed you're on a corporate network. Are you connected to VPN right now?"
- "Do you have local admin rights on this machine?"
- "Have you experienced certificate errors with Docker in the past?" (proxy detection)

### 4. Categorize results

Group findings into actionable categories:

**Ready:**
- All required tools installed and working
- Proceed directly to ideation

**Quick fixes:**
- Tools missing but can be installed now
- Offer to guide installation
- Examples: Docker, GitHub CLI, VS Code

**Blockers:**
- Access requests needed (VPN, admin rights, cloud access, GitHub org access)
- These require IT approval and may take time
- Provide clear instructions for requesting access

---

## How to Present Results to the User

### If everything passes:
"Great news -- your machine is all set up and ready to go! Let's start building your app."

### If quick fixes needed:
"Almost there! I need to install a couple of things first. This will just take a minute..."

Then either:
- Provide installation commands they can run
- Guide them through the installation process step by step

### If blockers exist:
"Before we can start building, you'll need a few things set up. Don't worry -- I'll walk you through each one.

Here's what you need:
1. [List only what's actually missing, with specific instructions]

[For enterprise blockers:]
Some of these may require IT approval. Once everything is ready, come back and type /make-it again -- I'll pick up right where we left off!"

---

## Notes for Skill Implementation

1. **Don't assume enterprise context:** Most developers aren't in restrictive corporate environments. Only check enterprise prerequisites if signals suggest it's needed.

2. **Be specific about what's missing:** Don't list all possible prerequisites -- only the ones that failed checks.

3. **Provide actionable guidance:** Installation commands, download URLs, or clear "contact IT" instructions.

4. **Cloud provider is optional:** Don't check cloud CLI unless the user has indicated they want to deploy somewhere specific.

5. **Proxy detection is reactive:** Only mention SSL-inspecting proxies if Docker builds fail with certificate errors. Don't pre-emptively ask about it.

6. **VS Code is optional but recommended:** The app works without it, but viewing code is much easier with an IDE.
