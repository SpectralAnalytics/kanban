---
name: deploy-to-github
description: >-
  Use this skill when the user asks to push code to GitHub, deploy to GitHub Pages,
  configure repository metadata/about section, run a sensitive data security scan,
  or set up CI/CD workflows for the Kanban project.
---

# Deploy to GitHub & Setup GitHub Pages CI/CD

This skill executes the project deployment pipeline to GitHub and GitHub Pages.

## Pipeline Steps Executed:
1. **Security Scan**: Checks files and commits for sensitive information (API keys, private keys, tokens, .env files).
2. **Repository Configuration**: Uses the provided or configured GitHub repository info.
3. **Commit & Push**: Commits pending changes and pushes branch to GitHub remote.
4. **CI/CD Setup**: Deploys via `.github/workflows/deploy-pages.yml` with GitHub Actions Pages provider.
5. **Repo About & Homepage**: Updates GitHub repository description, topics, and sets homepage to the live GitHub Pages URL (`https://<owner>.github.io/<repo>/`).

## Running the Command

In PowerShell:
```powershell
pwsh -File ./scripts/deploy.ps1
```

Or via npm:
```bash
npm run deploy
```

Custom repository parameter:
```powershell
pwsh -File ./scripts/deploy.ps1 -Repo "owner/repo" -Description "Custom description"
```
