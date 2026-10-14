# Mythos agent role

A scoped, least-privilege IAM role for the Mythos agent in the Gas-Lighting LLC project, and the Lambda function that
mints its sessions. Profile `gsl`, project Region `us-east-2`, new AWS experience. Nothing in this folder is deployed by
GitHub Pages.

## What it grants

The role `gsl-mythos-agent` carries one customer managed policy, `gsl-mythos-agent-policy`, and nothing else.

| service | scope | actions |
|---|---|---|
| S3 | one bucket: `gsl-mythos-<account id>` (created by the stack) or a bucket you name | list, get, put, delete objects; multipart upload; read bucket location and versioning |
| Lambda | functions named `mythos-*` in us-east-2 | create, get, update code and configuration, publish version, invoke, delete, tags, resource permissions, function URL config |
| Lambda | account-wide, us-east-2 only | list functions, account settings (these two cannot be scoped to a name) |
| IAM | exactly one role, `gsl-mythos-agent-lambda-exec` | pass it to Lambda and to no other service |
| CloudWatch Logs | log groups `/aws/lambda/mythos-*` in us-east-2 | read log streams and events (so a function can be debugged; delete the statement if you do not want it) |
| Secrets Manager | secrets named `mythos/*` in us-east-2 | get, describe, create, put, update, versions, tags; delete only with a recovery window, never force delete |
| Secrets Manager | account-wide, us-east-2 only | list secret names (cannot be scoped to a name) |
| STS | self | get caller identity |

One explicit deny pins everything Regional to us-east-2. S3, IAM PassRole and STS are exempt from that deny because they
are not Regional services, and the project's AWS rules allow us-east-1 only for global services anyway.

The Lambda execution role the agent may pass has basic execution (logs), read on `mythos/*` secrets, and get and put on
the agent's bucket. A function the agent creates can therefore never reach anything the agent itself cannot.

## How sessions are minted

The stack holds a Lambda function, `gsl-mint-mythos-session`, with its own execution role `gsl-mythos-agent-mint` that
may do exactly two things: assume `gsl-mythos-agent` and write its own logs. Every run:

1. generates a GUID;
2. calls STS AssumeRole on the agent role with the session name `mythos-<guid>` and a session tag `run=<guid>`;
3. prints a receipt to its log group (run id, expiry, assumed-role ARN, request id; no secret);
4. returns the run id, the expiry, and the five environment values the agent needs.

The GUID is the audit handle: the agent's assumed-role ARN is
`arn:aws:sts::<account id>:assumed-role/gsl-mythos-agent/mythos-<guid>`, so every action the agent takes shows that run
in CloudTrail, and the receipt in the function's log says when it was minted and when it expires.

Every call in this path is TLS: the console, the Lambda invoke, and the STS call the function makes. Nothing is written
to disk on your machine unless you choose the script path below, which deletes its temporary files.

The function's name is outside the agent's `mythos-*` prefix on purpose. The agent cannot read, change or invoke the
function that mints its own authority, and cannot read its log group.

**STS caps a session minted this way at one hour.** The function's execution role is itself a role session, and a role
session assuming another role is role chaining, which STS limits to 3600 seconds whatever the role's own ceiling says.
When a session expires, mint again.

### From the console

Lambda console, Region us-east-2, function `gsl-mint-mythos-session`, Test tab. Event:

```json
{ "durationSeconds": 3600 }
```

Press Test. The response is:

```json
{
  "run": "<guid>",
  "expiresAt": "2026-10-14T03:00:00Z",
  "assumedRole": "arn:aws:sts::<account id>:assumed-role/gsl-mythos-agent/mythos-<guid>",
  "env": {
    "AWS_ACCESS_KEY_ID": "...",
    "AWS_SECRET_ACCESS_KEY": "...",
    "AWS_SESSION_TOKEN": "...",
    "AWS_REGION": "us-east-2",
    "AWS_DEFAULT_REGION": "us-east-2"
  }
}
```

### From the script

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy-mythos-agent-role.ps1 -SessionOnly
```

The script invokes the same function and prints the same block.

## Giving the agent the session

The Claude Code cloud environment has no AWS identity. Put the five `env` values in the environment's settings (session
title bar, cloud environment, Edit; under Network secrets where offered, otherwise as environment variables). Start a new
session afterwards. Never paste them into a chat.

## Deploy

After `aws login --region us-east-2 --profile gsl`, from this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy-mythos-agent-role.ps1
```

The script validates the template, deploys the stack `gsl-mythos-agent-role` in us-east-2, prints the outputs, adds a
local profile named `mythos` that assumes the role from the `gsl` sign-in (for the AWS CLI and the Agent Toolkit's
aws-mcp on your own machine), and mints one session through the function.

On macOS or Linux the same by hand:

```bash
aws cloudformation deploy --template-file mythos-agent-role.yaml --stack-name gsl-mythos-agent-role \
  --capabilities CAPABILITY_NAMED_IAM --region us-east-2 --profile gsl
aws lambda invoke --function-name gsl-mint-mythos-session --cli-binary-format raw-in-base64-out \
  --payload '{"durationSeconds": 3600}' --region us-east-2 --profile gsl session.json
```

## What it deliberately does not grant

- No access keys. The role has no user behind it.
- No IAM beyond passing the one execution role: the agent cannot create roles, policies or users.
- No other bucket, no other function prefix, no other secret prefix, no other Region.
- No CloudFormation, API Gateway, DynamoDB, EC2 or anything else. Add a statement when a task needs it, not before.

## If the deploy or the mint is refused

In the new AWS experience the human's permissions are managed by AWS. If a call is denied, check the project's SCPs and
RCPs at https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html, then whether the deny names
the role's trust policy. The trust policy allows any principal of this account that itself holds `sts:AssumeRole`, which
includes the minting function's role.

## Not done here

This folder was written in a session whose container has no valid AWS credentials, so the stack has not been deployed,
the function has not run, and the template has been checked for YAML shape and the function's Python for syntax only.
The deploy script runs `validate-template` first, so a template error stops before anything is created.
