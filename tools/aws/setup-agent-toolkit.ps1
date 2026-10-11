# AWS Agent Toolkit setup for Gas-Lighting LLC
# Follows aws/agent-toolkit-for-aws setup-instructions/setup.md, steps 1 to 7.
# Profile gsl, project Region us-east-2, new AWS experience.
# The Agent Toolkit service itself only runs in us-east-1, so steps 5 and 6 use us-east-1 on purpose.
#
# Run from this folder in Windows PowerShell or PowerShell 7:
#   powershell -ExecutionPolicy Bypass -File .\setup-agent-toolkit.ps1
# Optional: -RulesDir <project folder> to place the AWS rules in that project's CLAUDE.md and AGENTS.md.

param(
    [string]$AwsProfile = "gsl",
    [string]$Region = "us-east-2",
    [string]$RulesDir = ""
)

$ErrorActionPreference = "Stop"
$Helper = Join-Path $PSScriptRoot "aws_toolkit_helper.py"
$Work = Join-Path $env:TEMP "gsl-aws-toolkit"
New-Item -ItemType Directory -Force -Path $Work | Out-Null

function Step([string]$n, [string]$what, [string]$why) {
    Write-Host ""
    Write-Host ("[Step {0}] {1}" -f $n, $what) -ForegroundColor Cyan
    if ($why) { Write-Host ("  Why: {0}" -f $why) -ForegroundColor DarkGray }
}
function Ok([string]$msg) { Write-Host ("  OK  {0}" -f $msg) -ForegroundColor Green }
function Warn([string]$msg) { Write-Host ("  !!  {0}" -f $msg) -ForegroundColor Yellow }
function Fail([string]$msg) {
    Write-Host ("  XX  {0}" -f $msg) -ForegroundColor Red
    Write-Host "  Stopped here. Fix the item above and run this script again; finished steps are safe to repeat." -ForegroundColor Red
    exit 1
}
function YesNo([string]$q) {
    while ($true) {
        $a = (Read-Host ("  {0} [y/n]" -f $q)).Trim().ToLower()
        if ($a -eq "y") { return $true }
        if ($a -eq "n") { return $false }
    }
}
function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = ($machine, $userPath, $env:Path -join ";")
}
function Run-Helper([string[]]$HelperArgs) {
    & uv.exe run --no-project --python 3.12 $Helper @HelperArgs
    return $LASTEXITCODE
}

Write-Host "AWS Agent Toolkit setup" -ForegroundColor White
Write-Host ("  Profile: {0}   Project Region: {1}   Experience: new AWS experience" -f $AwsProfile, $Region)

# ---------- Step 1 ----------
Step "1" "Determine operating system" "The installer differs by platform."
if ($env:OS -ne "Windows_NT") { Fail ("Expected Windows, found '{0}'. Use the macOS/Linux path in setup.md instead." -f $env:OS) }
Ok "Windows"

# ---------- Prerequisites ----------
Step "0" "Check prerequisites: PowerShell, uv, and access to awscli.amazonaws.com" "setup.md requires uv and network reach to the AWS installer."
$missing = @()
if (-not (Get-Command uv.exe -ErrorAction SilentlyContinue)) {
    Warn "uv is not installed. It runs the small Python helper that edits MCP configs safely."
    if (YesNo "Install uv now from astral.sh (user-level, no admin)?") {
        Invoke-Expression (Invoke-RestMethod -Uri "https://astral.sh/uv/install.ps1")
        Refresh-Path
        $env:Path = (Join-Path $env:USERPROFILE ".local\bin") + ";" + $env:Path
        if (-not (Get-Command uv.exe -ErrorAction SilentlyContinue)) { Fail "uv still not found after install. Open a new PowerShell window and rerun." }
        Ok "uv installed"
    } else { $missing += "uv" }
} else { Ok ("uv " + ((& uv.exe --version) -join " ")) }
try {
    Invoke-WebRequest -Uri "https://awscli.amazonaws.com" -Method Head -UseBasicParsing -TimeoutSec 20 | Out-Null
    Ok "awscli.amazonaws.com reachable"
} catch {
    if ($_.Exception.Response) { Ok "awscli.amazonaws.com reachable" }
    else { Warn "Could not reach https://awscli.amazonaws.com"; $missing += "network" }
}
if ($missing.Count -gt 0) {
    Warn ("Missing: {0}" -f ($missing -join ", "))
    if (-not (YesNo "Continue anyway?")) { Write-Host "Aborted at your request."; exit 0 }
}

# ---------- Step 2 ----------
Step "2" "Install or confirm the AWS CLI v2" "aws login and the agent-toolkit commands ship with current CLI v2 builds."
$aws = Get-Command aws.exe -ErrorAction SilentlyContinue
if ($aws) {
    Ok ((& aws.exe --version) -join " ")
} else {
    Write-Host "  Running the official AWS installer (user-local)."
    Invoke-Expression (Invoke-RestMethod -Uri "https://awscli.amazonaws.com/v2/install.ps1")
    Refresh-Path
    if (-not (Get-Command aws.exe -ErrorAction SilentlyContinue)) { Fail "aws.exe not on PATH after install. Close this window, open a new PowerShell, and rerun." }
    Ok ((& aws.exe --version) -join " ")
}
$allAws = @(Get-Command aws.exe -All -ErrorAction SilentlyContinue)
if ($allAws.Count -gt 1) {
    Warn "More than one aws.exe is on PATH; the first one wins:"
    $allAws | ForEach-Object { Write-Host ("      {0}" -f $_.Source) }
    Warn "If the version above is older than expected, uninstall the old one in Settings > Apps, or move the new folder earlier in PATH."
}

Write-Host ""
Write-Host "  Credentials from aws login last 12 hours and renew automatically for up to 90 days without signing in again in the browser." -ForegroundColor White

# ---------- Step 3 ----------
Step "3" ("Set Region {0} on profile {1}, then sign in" -f $Region, $AwsProfile) "Your project lives in one Region; a browser window opens for sign-in."
& aws.exe configure set region $Region --profile $AwsProfile
if ($LASTEXITCODE -ne 0) { Fail "Could not write the Region to ~/.aws/config." }
Write-Host "  A browser window will open. Sign in to your AWS project there, then come back here." -ForegroundColor White
& aws.exe login --region $Region --profile $AwsProfile
if ($LASTEXITCODE -ne 0) {
    Warn "Sign-in did not finish (closed browser, timeout, or no browser opened)."
    if (YesNo "Retry with the copy-a-link flow (--remote) instead?") {
        & aws.exe login --region $Region --profile $AwsProfile --remote
        if ($LASTEXITCODE -ne 0) {
            Fail ("Sign-in failed. If the error says the profile already has Access Key credentials, remove the aws_access_key_id and aws_secret_access_key lines under [{0}] in %USERPROFILE%\.aws\credentials, or rerun with -AwsProfile <new name>." -f $AwsProfile)
        }
    } else { Fail "Sign-in not completed." }
}
Ok "Signed in"

# ---------- Step 4 ----------
Step "4" "Verify access" "Confirms the credentials actually work before anything is configured on top of them."
$ident = & aws.exe sts get-caller-identity --profile $AwsProfile --output json
if ($LASTEXITCODE -ne 0) { Fail "get-caller-identity failed. Rerun this script to redo the sign-in." }
$id = $ident | ConvertFrom-Json
Ok ("Account {0}" -f $id.Account)
Ok ("Arn     {0}" -f $id.Arn)

# ---------- Step 5 ----------
Step "5" "Set up the Agent Toolkit (interactive wizard)" "Installs default AWS skills and writes an aws-mcp server entry into each AI tool it finds."
$pre = Join-Path $Work "aws-mcp-before.json"
$rc = Run-Helper @("scan", "--out", $pre)
if ($rc -ne 0) { Fail "Could not scan existing MCP configs." }
Write-Host "  Answer the wizard's prompts below." -ForegroundColor White
& aws.exe configure agent-toolkit --yes --region us-east-1 --profile $AwsProfile
if ($LASTEXITCODE -ne 0) {
    Warn "The wizard exited with an error. If it rejected --yes, this CLI build predates that flag; retrying without it."
    & aws.exe configure agent-toolkit --region us-east-1 --profile $AwsProfile
    if ($LASTEXITCODE -ne 0) { Fail "aws configure agent-toolkit failed. If credentials expired, rerun this script." }
}
Ok "Agent Toolkit configured"

Step "5b" ("Point every aws-mcp entry at profile {0}" -f $AwsProfile) "The generated entries fall back to the default profile and would fail to start without this."
Write-Host "  Only an env block is added. command, args, timeout and transport are left exactly as written. Each edited file gets a .bak copy first." -ForegroundColor DarkGray
$rc = Run-Helper @("patch", "--profile", $AwsProfile, "--pre", $pre)
if ($rc -eq 2) { Warn "No aws-mcp entry was found. The wizard may not have detected an AI tool; rerun step 5 after installing one." }
elseif ($rc -ne 0) { Fail "Patching MCP configs failed; see the message above. Backups sit next to each file." }
Write-Host ("  To use another AWS account later, run: aws login --profile <name>, add that name to the space-separated AWS_MCP_PROXY_PROFILES list in each MCP configuration file, and restart your AI tool.") -ForegroundColor White

# ---------- Step 6 ----------
Step "6" "Verify the Agent Toolkit" "Lists the remote skill catalog; a JSON list means the service and credentials both work."
$skillsRaw = & aws.exe agent-toolkit list-available-skills --region us-east-1 --profile $AwsProfile --output json
if ($LASTEXITCODE -ne 0) { Fail "list-available-skills failed. Update the AWS CLI (rerun step 2 after uninstalling the old one) and try again." }
$skillsFile = Join-Path $Work "available-skills.json"
$skillsRaw | Out-File -FilePath $skillsFile -Encoding utf8
try {
    $parsed = ($skillsRaw -join "`n") | ConvertFrom-Json
    $list = $null
    foreach ($prop in $parsed.PSObject.Properties) { if ($prop.Value -is [System.Array]) { $list = $prop.Value; break } }
    if ($parsed -is [System.Array]) { $list = $parsed }
    if ($list) { Ok ("{0} skills available; full list saved to {1}" -f $list.Count, $skillsFile) }
    else { Ok ("Catalog returned; saved to {0}" -f $skillsFile) }
} catch { Ok ("Catalog returned; saved to {0}" -f $skillsFile) }

# ---------- Step 7 ----------
Step "7" "Add the new-experience AWS rules to your project" "Agents read CLAUDE.md and AGENTS.md; the rules keep them inside your project's Region and service limits."
if (-not $RulesDir) {
    $RulesDir = (Read-Host "  Project folder for the rules (Enter to skip; the indiscipline-concepts repo already carries them)").Trim().Trim('"')
}
if ($RulesDir) {
    $rc = Run-Helper @("rules", "--dir", $RulesDir)
    if ($rc -ne 0) { Fail "Could not write the rules files." }
    Ok "Rules placed between BEGIN/END AWS Agent Toolkit markers; existing content kept."
} else { Warn "Skipped placing rules in a local folder." }

Write-Host ""
Write-Host "Setup is complete! Close this session and start a new one. Your AI tool will automatically use the rules and skill files we just installed. Try this as your first prompt:" -ForegroundColor Green
Write-Host ""
Write-Host "  Please make a single page webapp game and deploy it to AWS." -ForegroundColor White
Write-Host ""
Write-Host "If you're looking to explore what you can do on AWS, that prompt will get you started with a fun project. You can replace the game request with anything you'd like to build."
