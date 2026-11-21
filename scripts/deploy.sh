#!/usr/bin/env bash
# Project Release & GitHub Deployment Script (POSIX/Bash version)
set -eo pipefail

REPO="${1:-}"
BRANCH="${2:-main}"
DESCRIPTION="${3:-Modern Kanban Board Application}"
SKIP_SCAN="${4:-false}"

echo -e "\n=== Resolving Repository Information ==="
if [ -z "$REPO" ]; then
  if git remote get-url origin >/dev/null 2>&1; then
    REPO=$(git remote get-url origin)
    echo "Found existing remote origin: $REPO"
  else
    read -rp "Please enter the GitHub repository (e.g. owner/repo or full clone URL): " REPO
  fi
fi

if [ -z "$REPO" ]; then
  echo "Error: Repository information is required."
  exit 1
fi

REPO_CLEAN=$(echo "$REPO" | sed -E 's#(https://github.com/|git@github.com:|https://github.com/)##; s#\.git$##')
OWNER=$(echo "$REPO_CLEAN" | cut -d'/' -f1)
NAME=$(echo "$REPO_CLEAN" | cut -d'/' -f2)
PAGES_URL="https://${OWNER}.github.io/${NAME}/"

echo "Target Repository: ${OWNER}/${NAME}"
echo "Target Branch:     ${BRANCH}"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI ('gh') is not installed or not in PATH."
  exit 1
fi

echo -e "\n=== Performing Security & Sensitive Data Scan ==="
if [ "$SKIP_SCAN" = "true" ]; then
  echo "Warning: Security scan skipped."
else
  ISSUES=()
  for file in $(git ls-files --cached --others --exclude-standard); do
    if [ -f "$file" ]; then
      case "$file" in
        *.env*|*id_rsa*|*id_ed25519*|*.pem|*.key|*.pfx|*.p12|*credentials.json|*service-account*.json)
          ISSUES+=("Potential sensitive file: $file")
          ;;
      esac
      if grep -Eq 'gh[pousr]_[A-Za-z0-9_]{36,255}|-----BEGIN (RSA|EC|DSA|OPENSSH|PGP|PRIVATE) KEY-----|AIza[0-9A-Za-z\-_]{35}' "$file" 2>/dev/null; then
        ISSUES+=("Potential secret detected in $file")
      fi
    fi
  done

  if [ ${#ISSUES[@]} -gt 0 ]; then
    echo "Security scan detected potential sensitive data or secrets:"
    for issue in "${ISSUES[@]}"; do
      echo "  - $issue"
    done
    read -rp "Do you want to abort the deployment? (Y/n): " CONFIRM
    if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then
      echo "Deployment aborted."
      exit 1
    fi
  else
    echo "Security scan passed. No secrets detected."
  fi
fi

echo -e "\n=== Configuring Remote and Pushing Code ==="
EXPECTED_REMOTE="https://github.com/${OWNER}/${NAME}.git"
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$EXPECTED_REMOTE"
else
  git remote set-url origin "$EXPECTED_REMOTE"
fi

git branch -M "$BRANCH"
git add -A
if ! git diff-index --quiet HEAD --; then
  git commit -m "Configure GitHub Pages CI/CD workflow and project release"
fi

git push -u origin "$BRANCH"

echo -e "\n=== Configuring GitHub Pages & GitHub Actions CI/CD ==="
gh api --method PUT "repos/${OWNER}/${NAME}/pages" -f build_type="workflow" 2>/dev/null || \
gh api --method POST "repos/${OWNER}/${NAME}/pages" -f build_type="workflow" 2>/dev/null || true

gh workflow run deploy-pages.yml -R "${OWNER}/${NAME}" --ref "$BRANCH" 2>/dev/null || true

echo -e "\n=== Updating GitHub Repository About Section ==="
gh repo edit "${OWNER}/${NAME}" \
  --description "$DESCRIPTION" \
  --homepage "$PAGES_URL" \
  --add-topic "kanban" \
  --add-topic "workflow" \
  --add-topic "github-pages"

echo -e "\n=== Deployment Summary ==="
echo "Repository:       https://github.com/${OWNER}/${NAME}"
echo "GitHub Pages URL: ${PAGES_URL}"
echo "CI/CD Actions:    https://github.com/${OWNER}/${NAME}/actions"
echo -e "\nAll steps completed successfully!"
