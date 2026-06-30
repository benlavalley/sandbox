# install.ps1 — Install the sandbox CLI on Windows by cloning the repo and
# building it from source with Bun (no prebuilt release required).
#
# Quick start (PowerShell):
#   irm https://raw.githubusercontent.com/benlavalley/sandbox/windows-support/scripts/install.ps1 | iex
#
# Env overrides:
#   $env:SANDBOX_REPO   = "benlavalley/sandbox"
#   $env:SANDBOX_BRANCH = "windows-support"
#   $env:PREFIX         = "$env:LOCALAPPDATA\Programs\sandbox"   # install dir

$ErrorActionPreference = "Stop"

$Repo   = if ($env:SANDBOX_REPO)   { $env:SANDBOX_REPO }   else { "benlavalley/sandbox" }
$Branch = if ($env:SANDBOX_BRANCH) { $env:SANDBOX_BRANCH } else { "windows-support" }
$InstallDir = if ($env:PREFIX) { $env:PREFIX } else { "$env:LOCALAPPDATA\Programs\sandbox" }

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "git is required. Install from https://git-scm.com/download/win"
}

if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
  Write-Host "==> Installing bun"
  Invoke-RestMethod bun.sh/install.ps1 | Invoke-Expression
  $env:Path = "$env:USERPROFILE\.bun\bin;$env:Path"
}

$Work = Join-Path $env:TEMP ("sandbox-" + [System.Guid]::NewGuid().ToString("N"))
try {
  Write-Host "==> Cloning $Repo@$Branch"
  git clone --depth 1 --branch $Branch "https://github.com/$Repo.git" $Work

  Push-Location (Join-Path $Work "cli")
  Write-Host "==> Installing dependencies"
  bun install --frozen-lockfile

  Write-Host "==> Building sandbox.exe"
  bun build --compile --target=bun-windows-x64 src/index.ts --outfile sandbox.exe

  Copy-Item -Force sandbox.exe (Join-Path $InstallDir "sandbox.exe")
  Pop-Location

  Write-Host ""
  Write-Host "==> Installed: $InstallDir\sandbox.exe"
  Write-Host ""
  Write-Host "Add to PATH for this session:"
  Write-Host "  `$env:Path = `"$InstallDir;`$env:Path`""
  Write-Host "Or permanently (new shells):"
  Write-Host "  setx PATH `"$InstallDir;%PATH%`""
  Write-Host ""
  Write-Host "Then, with Docker Desktop running:"
  Write-Host "  sandbox serve"
}
finally {
  if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
}
