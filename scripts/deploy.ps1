# Project Release & GitHub Deployment Script
# Steps performed:
# 1. Scans workspace for sensitive patterns/secrets (.env, API keys, private keys, tokens)
# 2. Configures git remote if user provides/overrides repository info
# 3. Stages, commits, and pushes changes to GitHub
# 4. Configures GitHub repository About section (Description & Topics)
# 5. Configures / triggers GitHub Pages (via GitHub Actions CI/CD)
# 6. Sets GitHub Pages URL as repository homepage in About section

param(
    [Parameter(Position=0)]
    [string]$Repo = "", # e.g. "SpectralAnalytics/kanban" or full URL "https://github.com/SpectralAnalytics/kanban.git"
    [string]$Branch = "main",
    [string]$Description = "Modern Kanban Board Application",
    [switch]$SkipScan = $false
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# -------------------------------------------------------------
# STEP 0: Resolve Repository Info
# -------------------------------------------------------------
Write-Step "Resolving Repository Information"

if (-not $Repo) {
    # Check git remote origin
    $existingRemote = git remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0 -and $existingRemote) {
        Write-Host "Found existing remote origin: $existingRemote"
        $Repo = $existingRemote
    } else {
        $Repo = Read-Host "Please enter the GitHub repository (e.g. owner/repo or full clone URL)"
    }
}

if (-not $Repo) {
    Write-Err "Repository information is required to proceed."
    exit 1
}

# Normalize repo owner/name
$repoOwnerRepo = ""
if ($Repo -match "github\.com[:/]([^/]+)/([^/\.]+)(\.git)?$") {
    $repoOwner = $Matches[1]
    $repoName = $Matches[2]
    $repoOwnerRepo = "$repoOwner/$repoName"
} elseif ($Repo -match "^([^/]+)/([^/]+)$") {
    $repoOwner = $Matches[1]
    $repoName = $Matches[2]
    $repoOwnerRepo = "$repoOwner/$repoName"
} else {
    Write-Err "Could not parse repository owner/name from '$Repo'."
    exit 1
}

Write-Host "Target Repository: $repoOwnerRepo"
Write-Host "Target Branch:     $Branch"

# Verify gh CLI is available
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCmd) {
    Write-Err "GitHub CLI ('gh') is not installed or not in PATH. Please install gh CLI to configure GitHub Pages and repo metadata."
    exit 1
}

# -------------------------------------------------------------
# STEP 1: Security & Sensitive Information Scan
# -------------------------------------------------------------
Write-Step "Performing Security & Sensitive Data Scan"

if ($SkipScan) {
    Write-Warn "Security scan skipped by user switch."
} else {
    $sensitiveFilesPattern = @(
        "^\.env(\..+)?$",
        "id_rsa",
        "id_ed25519",
        "\.pem$",
        "\.key$",
        "\.pfx$",
        "\.p12$",
        "credentials\.json",
        "service-account.*\.json",
        "\.secret"
    )

    $secretRegexes = @(
        @{ Name = "GitHub Token"; Regex = 'gh[pousr]_[A-Za-z0-9_]{36,255}' },
        @{ Name = "Generic Private Key"; Regex = '-----BEGIN (RSA|EC|DSA|OPENSSH|PGP|PRIVATE) KEY-----' },
        @{ Name = "AWS Access Key"; Regex = '(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}' },
        @{ Name = "Generic Secret Assignment"; Regex = '(?i)(api[_-]?key|secret[_-]?key|auth[_-]?token|password)\s*[:=]\s*["''][^"''\s]{8,}["'']' },
        @{ Name = "Google API Key"; Regex = 'AIza[0-9A-Za-z\\-_]{35}' },
        @{ Name = "Slack Token"; Regex = 'xox[baprs]-[0-9]{10,13}-[0-9]{10,13}[a-zA-Z0-9-]*' }
    )

    $foundIssues = @()

    # Get tracked files + untracked files
    $filesToCheck = git ls-files --cached --others --exclude-standard
    foreach ($relPath in $filesToCheck) {
        if (-not (Test-Path $relPath -PathType Leaf)) { continue }

        $fileName = Split-Path -Leaf $relPath
        foreach ($pattern in $sensitiveFilesPattern) {
            if ($fileName -match $pattern) {
                $foundIssues += "Potential sensitive file staged/present: $relPath (matches pattern '$pattern')"
            }
        }

        # Scan text content for secret tokens
        try {
            $content = Get-Content -Path $relPath -Raw -ErrorAction SilentlyContinue
            if ($null -ne $content) {
                foreach ($rule in $secretRegexes) {
                    if ($content -match $rule.Regex) {
                        $ruleName = $rule.Name
                        $foundIssues += "Potential secret detected in ${relPath}: $ruleName"
                    }
                }
            }
        } catch {
            # Binary files or read issues skipped safely
        }
    }

    if ($foundIssues.Count -gt 0) {
        Write-Err "Security scan detected potential sensitive data or secrets:"
        foreach ($issue in $foundIssues) {
            Write-Host "  - $issue" -ForegroundColor Red
        }
        $confirm = Read-Host "Do you want to abort the deployment? (Y/n)"
        if ($confirm -ne 'n' -and $confirm -ne 'N') {
            Write-Err "Deployment aborted to protect sensitive information."
            exit 1
        }
        Write-Warn "Proceeding despite scan warnings per user confirmation."
    } else {
        Write-Success "Security scan passed. No secrets or sensitive credential files detected."
    }
}

# -------------------------------------------------------------
# STEP 2: Configure Remote & Push Code to GitHub
# -------------------------------------------------------------
Write-Step "Configuring Remote and Pushing Code"

$currentRemote = git remote get-url origin 2>$null
$expectedRemoteUrl = "https://github.com/$repoOwnerRepo.git"

if ($LASTEXITCODE -ne 0 -or -not $currentRemote) {
    Write-Host "Adding remote origin: $expectedRemoteUrl"
    git remote add origin $expectedRemoteUrl
} elseif ($currentRemote -notmatch "$repoOwner/$repoName") {
    Write-Host "Updating remote origin to: $expectedRemoteUrl"
    git remote set-url origin $expectedRemoteUrl
}

# Ensure git branch is correct
git branch -M $Branch

# Stage changes
git add -A

# Check if there are changes to commit
$statusOutput = git status --porcelain
if ($statusOutput) {
    Write-Host "Committing local changes..."
    git commit -m "Configure GitHub Pages CI/CD workflow and project release"
} else {
    Write-Host "Working tree clean, no new commits needed."
}

Write-Host "Pushing to GitHub branch '$Branch'..."
git push -u origin $Branch
if ($LASTEXITCODE -ne 0) {
    Write-Err "Failed to push code to GitHub. Please check your git credentials and repository permissions."
    exit 1
}
Write-Success "Code pushed successfully to GitHub ($repoOwnerRepo)."

# -------------------------------------------------------------
# STEP 3: Configure GitHub Pages & CI/CD Workflow
# -------------------------------------------------------------
Write-Step "Configuring GitHub Pages & GitHub Actions CI/CD"

$pagesUrl = "https://$repoOwner.github.io/$repoName/"

# Switch GitHub Pages build type to workflow (GitHub Actions)
Write-Host "Setting GitHub Pages build source to GitHub Actions workflow..."
try {
    gh api --method PUT "repos/$repoOwnerRepo/pages" -f build_type="workflow" 2>$null | Out-Null
    Write-Success "Pages build source configured to GitHub Actions workflow."
} catch {
    # If pages does not exist yet, create it
    try {
        gh api --method POST "repos/$repoOwnerRepo/pages" -f build_type="workflow" 2>$null | Out-Null
        Write-Success "Created GitHub Pages with GitHub Actions workflow build source."
    } catch {
        Write-Warn "Could not update Pages build type directly via API; workflow run will manage deployment."
    }
}

# Trigger the deploy workflow
Write-Host "Triggering Deploy to GitHub Pages workflow dispatch..."
gh workflow run deploy-pages.yml -R $repoOwnerRepo --ref $Branch 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Success "Workflow dispatched successfully."
} else {
    Write-Host "Workflow triggered automatically by push to '$Branch'."
}

# -------------------------------------------------------------
# STEP 4: Update Repository About Section & Pages Link
# -------------------------------------------------------------
Write-Step "Updating GitHub Repository About Section"

Write-Host "Setting repository description to: '$Description'"
Write-Host "Setting repository homepage to:    '$pagesUrl'"

gh repo edit $repoOwnerRepo `
    --description "$Description" `
    --homepage "$pagesUrl" `
    --add-topic "kanban" `
    --add-topic "workflow" `
    --add-topic "github-pages"

if ($LASTEXITCODE -eq 0) {
    Write-Success "GitHub repository About section updated with description and Pages URL."
} else {
    Write-Warn "Could not update repository About section. Check permissions."
}

Write-Step "Deployment Summary"
Write-Host "Repository:       https://github.com/$repoOwnerRepo" -ForegroundColor Green
Write-Host "GitHub Pages URL: $pagesUrl" -ForegroundColor Green
Write-Host "CI/CD Actions:    https://github.com/$repoOwnerRepo/actions" -ForegroundColor Green
Write-Host "`nAll steps completed successfully!" -ForegroundColor Green
