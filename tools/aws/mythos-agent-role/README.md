# Mythos agent role

A scoped, least-privilege IAM role for the Mythos agent in the Gas-Lighting LLC project. Profile `gsl`, project Region
`us-east-2`, new AWS experience. Nothing in this folder is deployed by GitHub Pages.

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

## What it deliberately does not grant

- No access keys. The role has no user behind it. The owner assumes it with the `gsl` sign-in and hands the agent a
  session that expires (4 hours by default, 12 at most).
- No IAM beyond passing the one execution role: the agent cannot create roles, policies or users.
- No other bucket, no other function prefix, no other secret prefix, no other Region.
- No CloudFormation, API Gateway, DynamoDB, EC2 or anything else. Add a statement when a task needs it, not before.

## Deploy

After `aws login --region us-east-2 --profile gsl`, from this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy-mythos-agent-role.ps1
```

The script validates the template, deploys the stack `gsl-mythos-agent-role` in us-east-2, prints the outputs, adds a
local profile named `mythos` that assumes the role from the `gsl` sign-in, and mints one session.

On macOS or Linux the same steps by hand:

```bash
aws cloudformation deploy --template-file mythos-agent-role.yaml --stack-name gsl-mythos-agent-role \
  --capabilities CAPABILITY_NAMED_IAM --region us-east-2 --profile gsl
aws cloudformation describe-stacks --stack-name gsl-mythos-agent-role --region us-east-2 --profile gsl \
  --query "Stacks[0].Outputs"
aws sts assume-role --role-arn arn:aws:iam::<account id>:role/gsl-mythos-agent \
  --role-session-name mythos-agent --duration-seconds 14400 --profile gsl
```

## Giving the agent the session

The Claude Code cloud environment has no AWS identity. Put the three values the script prints, plus the Region, in the
environment's settings (session title bar, cloud environment, Edit; under Network secrets where offered, otherwise as
environment variables):

```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
AWS_REGION=us-east-2
AWS_DEFAULT_REGION=us-east-2
```

Start a new session afterwards. When the session expires, run the script again with `-SessionOnly` and replace the three
values. Never paste them into a chat.

For local tools, the `mythos` profile the script writes lets the AWS CLI and the Agent Toolkit's aws-mcp run as the
scoped role: `aws sts get-caller-identity --profile mythos` should answer with the role's assumed-role ARN. To make the
toolkit use it, add `mythos` to `AWS_MCP_PROXY_PROFILES` in its MCP config and restart the AI tool.

## If assume-role is refused

In the new AWS experience the human's permissions are managed by AWS. If `sts:AssumeRole` on this role is denied for
your signed-in identity, check two things in order: the project's SCPs and RCPs at
https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html, then whether the deny names the
role's trust policy. The trust policy allows any principal of this account that itself holds `sts:AssumeRole`; it does
not name your identity because the managed identity's ARN is not stable to pin.

## Not done here

This folder was written in a session whose container has no valid AWS credentials, so the stack has not been deployed
and the template has been checked for YAML shape only, not by `validate-template`. The deploy script runs
`validate-template` first, so a template error stops before anything is created.
