# Deploy the scoped Mythos agent role for Gas-Lighting LLC, then mint a bounded session for the agent.
# Profile gsl, project Region us-east-2, new AWS experience. IAM is global; the stack is created in the project Region.
#
# Run from this folder in Windows PowerShell or PowerShell 7 after `aws login --profile gsl`:
#   powershell -ExecutionPolicy Bypass -File .\deploy-mythos-agent-role.ps1
# Options:
#   -BucketName <name>        use an existing bucket instead of creating gsl-mythos-<account id>
#   -MaxSessionSeconds 14400  1 h = 3600, 2 h = 7200, 4 h = 14400 (default), 8 h = 28800, 12 h = 43200
#   -SessionOnly              skip the deploy and only mint a new session for the agent
#   -NoSession                deploy only; print the role ARN and stop
#
# Nothing here prints a long-lived key, because the role has none. The session it prints expires.

param(
    [string]$AwsProfile = "gsl",
    [string]$Region = "us-east-2",
    [string]$StackName = "gsl-mythos-agent-role",
    [string]$RoleName = "gsl-mythos-agent",
    [string]$BucketName = "",
    [int]$MaxSessionSeconds = 14400,
    [switch]$SessionOnly,
    [switch]$NoSession
)

$ErrorActionPreference = "Stop"
$Template = Join-Path $PSScriptRoot "mythos-agent-role.yaml"

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

Write-Host "Mythos agent role" -ForegroundColor White
Write-Host ("  Profile: {0}   Project Region: {1}   Stack: {2}   Role: {3}" -f $AwsProfile, $Region, $StackName, $RoleName)

# ---------- Step 1 ----------
Step "1" "Confirm the signed-in identity" "The role trusts this account; the deploy and the assume-role both run as you."
if (-not (Get-Command aws.exe -ErrorAction SilentlyContinue)) { Fail "aws.exe not found. Run setup-agent-toolkit.ps1 first, or install the AWS CLI v2." }
$ident = & aws.exe sts get-caller-identity --profile $AwsProfile --output json
if ($LASTEXITCODE -ne 0) { Fail ("Not signed in. Run: aws login --region {0} --profile {1}" -f $Region, $AwsProfile) }
$id = $ident | ConvertFrom-Json
Ok ("Account {0}" -f $id.Account)
Ok ("Arn     {0}" -f $id.Arn)
$RoleArn = ("arn:aws:iam::{0}:role/{1}" -f $id.Account, $RoleName)

if (-not $SessionOnly) {
    # ---------- Step 2 ----------
    Step "2" "Validate the template" "A syntax or schema error is caught before anything is created."
    & aws.exe cloudformation validate-template --template-body ("file://" + $Template) --region $Region --profile $AwsProfile --output json | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "validate-template rejected mythos-agent-role.yaml." }
    Ok "Template is valid"

    # ---------- Step 3 ----------
    Step "3" ("Deploy stack {0}" -f $StackName) "One stack holds the role, its policy, the Lambda execution role it may pass, and the bucket. Rerunning updates in place."
    $params = @(
        ("RoleName=" + $RoleName),
        ("BucketName=" + $BucketName),
        ("MaxSessionSeconds=" + $MaxSessionSeconds),
        ("ProjectRegion=" + $Region)
    )
    & aws.exe cloudformation deploy `
        --template-file $Template `
        --stack-name $StackName `
        --capabilities CAPABILITY_NAMED_IAM `
        --parameter-overrides @params `
        --no-fail-on-empty-changeset `
        --region $Region --profile $AwsProfile
    if ($LASTEXITCODE -ne 0) {
        Warn "Deploy failed. Read the stack events in the CloudFormation console in your project Region."
        Warn "If the error is an explicit deny from a service control policy, the managed SCPs of the new AWS experience block this call; see the README."
        Fail "Stack not deployed."
    }
    Ok "Stack deployed"

    # ---------- Step 4 ----------
    Step "4" "Read the outputs" "The role ARN is what every later session is minted from."
    $outRaw = & aws.exe cloudformation describe-stacks --stack-name $StackName --region $Region --profile $AwsProfile --query "Stacks[0].Outputs" --output json
    if ($LASTEXITCODE -ne 0) { Fail "describe-stacks failed." }
    $outs = $outRaw | ConvertFrom-Json
    foreach ($o in $outs) { Ok ("{0,-24} {1}" -f $o.OutputKey, $o.OutputValue) }
    $RoleArn = ($outs | Where-Object { $_.OutputKey -eq "RoleArn" }).OutputValue

    # ---------- Step 5 ----------
    Step "5" ("Add profile 'mythos' to ~/.aws/config") "Local tools (the AWS CLI, the Agent Toolkit's aws-mcp) can then run as the scoped role by name, with the gsl sign-in as the source."
    & aws.exe configure set role_arn $RoleArn --profile mythos
    & aws.exe configure set source_profile $AwsProfile --profile mythos
    & aws.exe configure set region $Region --profile mythos
    & aws.exe configure set role_session_name mythos-agent --profile mythos
    & aws.exe configure set duration_seconds $MaxSessionSeconds --profile mythos
    Ok "Profile mythos -> $RoleArn (source: $AwsProfile)"
    Write-Host "  To give the Agent Toolkit's aws-mcp this scope, add mythos to AWS_MCP_PROXY_PROFILES in its MCP config and restart the AI tool." -ForegroundColor White
}

if ($NoSession) { Write-Host ""; Write-Host ("Role ready: {0}" -f $RoleArn) -ForegroundColor Green; exit 0 }

# ---------- Step 6 ----------
Step "6" ("Mint a session for the agent ({0} s)" -f $MaxSessionSeconds) "The cloud session has no AWS identity of its own. It gets these three values as environment secrets and nothing else; they expire."
$sessRaw = & aws.exe sts assume-role --role-arn $RoleArn --role-session-name mythos-agent --duration-seconds $MaxSessionSeconds --profile $AwsProfile --output json
if ($LASTEXITCODE -ne 0) {
    Warn "assume-role was refused."
    Warn "If the message is AccessDenied, your signed-in identity is not allowed sts:AssumeRole on this role. In the new AWS experience the human permissions are managed by AWS; see the README for what to check."
    Fail "No session minted."
}
$sess = ($sessRaw | ConvertFrom-Json).Credentials
Ok ("Session expires at {0} (UTC)" -f $sess.Expiration)
Write-Host ""
Write-Host "Put these in the Claude Code cloud environment (session title bar > cloud environment > Edit > Network secrets, or environment variables)." -ForegroundColor White
Write-Host "Set the Region too. Start a new session afterwards; the running one does not pick them up." -ForegroundColor White
Write-Host ""
Write-Host ("AWS_ACCESS_KEY_ID={0}" -f $sess.AccessKeyId)
Write-Host ("AWS_SECRET_ACCESS_KEY={0}" -f $sess.SecretAccessKey)
Write-Host ("AWS_SESSION_TOKEN={0}" -f $sess.SessionToken)
Write-Host ("AWS_REGION={0}" -f $Region)
Write-Host ("AWS_DEFAULT_REGION={0}" -f $Region)
Write-Host ""
Write-Host "When the session expires, run this script again with -SessionOnly and replace the three values." -ForegroundColor DarkGray
