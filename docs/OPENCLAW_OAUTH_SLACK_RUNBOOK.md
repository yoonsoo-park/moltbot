# OpenClaw OAuth + Slack Runbook

## Purpose

This runbook documents the operational procedure used to:

1. delete an existing Bedrock-based stack
2. redeploy OpenClaw with OpenAI Codex/ChatGPT OAuth
3. keep the Gateway private behind SSM port forwarding only
4. prepare Slack backend connectivity with Socket Mode

This is an operator runbook, not a generic quickstart.

## Target Environment

- AWS profile: `aws-dimly`
- AWS region: `us-east-1`
- Old stack: `openclaw-bedrock`
- New stack: `openclaw-oauth`
- Template: `clawdbot-bedrock.yaml`
- Private template bucket: `openclaw-cfn-templates-831597648506-us-east-1`
- Template object key: `openclaw-oauth/clawdbot-bedrock.yaml`

## Important Notes

- The current Linux template is larger than CloudFormation inline `TemplateBody` limits. Use `TemplateURL`, not `--template-body file://...`.
- For OpenAI OAuth on OpenClaw `2026.4.27`, the correct provider is `openai-codex`.
- `openclaw models auth login --provider openai` is the API key flow, not the OAuth flow.
- Public access stays disabled in this runbook. The Gateway should only bind to loopback and be accessed through SSM port forwarding.
- Slack should use Socket Mode. Do not configure inbound public Slack HTTP request URLs in this flow.

## Deployment Parameters

- `OpenAIModel=gpt-5.3`
- `InstanceType=c7g.large`
- `CreateVPCEndpoints=false`
- `EnableMonitoring=true`
- `EnableSandbox=true`
- `EnablePublicAccess=false`
- `EnableWAF=false`
- `EnableDataProtection=true`

## 1. Inspect Current State

```bash
aws cloudformation describe-stacks \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-bedrock

aws cloudformation describe-stacks \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-oauth
```

Expected:

- `openclaw-bedrock` exists and is the old stack to replace
- `openclaw-oauth` does not exist yet

## 2. Delete Old Stack

```bash
aws cloudformation delete-stack \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-bedrock

aws cloudformation wait stack-delete-complete \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-bedrock
```

If you need visibility while deletion is running:

```bash
aws cloudformation describe-stack-events \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-bedrock \
  --max-items 20
```

## 3. Upload Template to S3

Create the private deployment bucket once:

```bash
aws s3api create-bucket \
  --profile aws-dimly \
  --region us-east-1 \
  --bucket openclaw-cfn-templates-831597648506-us-east-1

aws s3api put-public-access-block \
  --profile aws-dimly \
  --region us-east-1 \
  --bucket openclaw-cfn-templates-831597648506-us-east-1 \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --profile aws-dimly \
  --region us-east-1 \
  --bucket openclaw-cfn-templates-831597648506-us-east-1 \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Upload the template used for deployment:

```bash
aws s3api put-object \
  --profile aws-dimly \
  --region us-east-1 \
  --bucket openclaw-cfn-templates-831597648506-us-east-1 \
  --key openclaw-oauth/clawdbot-bedrock.yaml \
  --body clawdbot-bedrock.yaml \
  --server-side-encryption AES256
```

## 4. Validate Template

```bash
aws cloudformation validate-template \
  --profile aws-dimly \
  --region us-east-1 \
  --template-url \
  https://openclaw-cfn-templates-831597648506-us-east-1.s3.us-east-1.amazonaws.com/openclaw-oauth/clawdbot-bedrock.yaml
```

Expected:

- validation succeeds
- capability requirement includes `CAPABILITY_IAM`

## 5. Create OAuth Stack

```bash
aws cloudformation create-stack \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-oauth \
  --template-url \
  https://openclaw-cfn-templates-831597648506-us-east-1.s3.us-east-1.amazonaws.com/openclaw-oauth/clawdbot-bedrock.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters \
    ParameterKey=OpenAIModel,ParameterValue=gpt-5.3 \
    ParameterKey=InstanceType,ParameterValue=c7g.large \
    ParameterKey=CreateVPCEndpoints,ParameterValue=false \
    ParameterKey=EnableMonitoring,ParameterValue=true \
    ParameterKey=EnableSandbox,ParameterValue=true \
    ParameterKey=EnablePublicAccess,ParameterValue=false \
    ParameterKey=EnableWAF,ParameterValue=false \
    ParameterKey=EnableDataProtection,ParameterValue=true

aws cloudformation wait stack-create-complete \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-oauth
```

If stack creation looks stalled, check events:

```bash
aws cloudformation describe-stack-events \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-oauth \
  --max-items 20
```

## 6. Verify Basic Outputs

```bash
aws cloudformation describe-stacks \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-oauth
```

Expected:

- stack status is `CREATE_COMPLETE`
- output `InstanceId` exists
- output `OpenAIModelInUse` is `gpt-5.3`
- no public CloudFront URL output is present
- access instructions point to SSM port forwarding

## 7. Get Instance ID

```bash
INSTANCE_ID=$(aws cloudformation describe-stacks \
  --profile aws-dimly \
  --region us-east-1 \
  --stack-name openclaw-oauth \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text)

echo "$INSTANCE_ID"
```

## 8. Start SSM Shell

```bash
aws ssm start-session \
  --profile aws-dimly \
  --region us-east-1 \
  --target "$INSTANCE_ID"
```

On the instance:

```bash
sudo -iu ubuntu
```

## 9. Complete OpenAI OAuth

Use the correct OAuth provider:

```bash
openclaw models auth login --provider openai-codex
```

If the CLI needs explicit method selection:

```bash
openclaw models auth login --provider openai-codex --method oauth
```

Do not use this for OAuth:

```bash
openclaw models auth login --provider openai
```

That path prompts for an OpenAI API key.

After login:

```bash
openclaw models status --probe
systemctl --user restart openclaw-gateway
openclaw gateway status
```

Expected:

- configured primary model is `openai-codex/gpt-5.3`
- gateway is running
- connectivity probe is `ok`

## 10. Port Forward Gateway UI

From your local machine:

```bash
aws ssm start-session \
  --profile aws-dimly \
  --region us-east-1 \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'
```

In a separate local shell, get the gateway token:

```bash
aws ssm get-parameter \
  --profile aws-dimly \
  --region us-east-1 \
  --name /openclaw/openclaw-oauth/gateway-token \
  --with-decryption \
  --query Parameter.Value \
  --output text
```

Open:

```text
http://localhost:18789/?token=<token>
```

## 11. Prepare Slack Socket Mode

OpenClaw `2026.4.27` already includes the Slack channel runtime used here. Do not install the latest `@openclaw/slack` plugin unless OpenClaw itself has also been upgraded to a compatible version. The latest plugin may require a newer plugin API than `2026.4.27`.

Remove stale plugin entries if warnings mention missing `openai` or `openai-codex` plugins:

```bash
sudo -iu ubuntu
openclaw config unset plugins.entries.openai-codex || true
openclaw config unset plugins.entries.openai || true
```

Create a Slack app with Socket Mode enabled, then collect:

- App-Level Token: `xapp-...`
- Bot User OAuth Token: `xoxb-...`

Required Slack token configuration:

- App-Level Token has `connections:write`
- Bot token scopes include `app_mentions:read`, `assistant:write`, `channels:history`, `channels:read`, `chat:write`, `commands`, `groups:history`, `groups:read`, `im:history`, `im:read`, `im:write`, and `users:read`
- The app has been installed or reinstalled to the workspace after scope changes

Write the tokens to `~/.openclaw/.env`. Keep each token on its own physical line:

```bash
read -rsp "Slack App-Level Token (xapp-...): " SLACK_APP_TOKEN; echo
read -rsp "Slack Bot User OAuth Token (xoxb-...): " SLACK_BOT_TOKEN; echo

umask 077
touch ~/.openclaw/.env
sed -i '/^SLACK_APP_TOKEN=/d;/^SLACK_BOT_TOKEN=/d' ~/.openclaw/.env
printf 'SLACK_APP_TOKEN=%s\n' "$SLACK_APP_TOKEN" >> ~/.openclaw/.env
printf 'SLACK_BOT_TOKEN=%s\n' "$SLACK_BOT_TOKEN" >> ~/.openclaw/.env
```

Verify the tokens directly against Slack before restarting OpenClaw:

```bash
BOT=$(grep '^SLACK_BOT_TOKEN=' ~/.openclaw/.env | tail -1 | cut -d= -f2-)
APP=$(grep '^SLACK_APP_TOKEN=' ~/.openclaw/.env | tail -1 | cut -d= -f2-)

curl -sS -H "Authorization: Bearer ${BOT}" https://slack.com/api/auth.test
curl -sS -X POST -H "Authorization: Bearer ${APP}" https://slack.com/api/apps.connections.open
```

Expected:

- `auth.test` returns `"ok":true`
- `apps.connections.open` returns `"ok":true` and a `wss://...` URL

Configure the Slack channel with `openclaw config set`. `openclaw config patch` is not available in OpenClaw `2026.4.27`:

```bash
openclaw config set channels.slack.mode socket
openclaw config set channels.slack.appToken \
  --ref-provider default \
  --ref-source env \
  --ref-id SLACK_APP_TOKEN
openclaw config set channels.slack.botToken \
  --ref-provider default \
  --ref-source env \
  --ref-id SLACK_BOT_TOKEN

openclaw config validate
systemctl --user restart openclaw-gateway
openclaw gateway status
```

## 12. Slack Verification

Check logs:

```bash
journalctl --user -u openclaw-gateway.service -n 120 --no-pager | grep -i slack
```

Expected:

- logs show `[slack] socket mode connected`
- OpenClaw gateway remains healthy after restart
- `openclaw gateway status` shows `Connectivity probe: ok`
- Slack app shows Socket Mode connected
- the bot can receive a DM or an app mention

On first contact, Slack may reply:

```text
OpenClaw: access not configured.
Your Slack user id: <USER_ID>
Pairing code: <CODE>
Ask the bot owner to approve with:
openclaw pairing approve slack <CODE>
```

Approve that sender on the instance:

```bash
openclaw pairing approve slack <CODE>
```

Expected:

```text
Approved slack sender <USER_ID>.
```

Then retry the DM or app mention.

## 13. Troubleshooting

### Symptom: `openclaw models auth login --provider openai` asks for API key

Cause:

- wrong provider id

Fix:

```bash
openclaw models auth login --provider openai-codex
```

### Symptom: CloudFormation validate/create fails with `templateBody` too large

Cause:

- inline template body exceeded the 51,200 byte limit

Fix:

- upload to S3
- use `--template-url`

### Symptom: Gateway starts but model auth is wrong

Check:

```bash
grep -nE 'openai-codex|primary|baseUrl|api' ~/.openclaw/openclaw.json
openclaw models status --plain
openclaw gateway status
```

Expected key lines:

- provider id `openai-codex`
- primary model `openai-codex/gpt-5.3`
- `baseUrl` set to `https://api.openai.com/v1`

### Symptom: Gateway must stay private

Check:

```bash
ss -tlnp | grep 18789
```

Expected:

- listening on `127.0.0.1:18789`
- not exposed publicly

### Symptom: Slack logs show `invalid_auth` or `not_authed`

Causes:

- token copied incorrectly
- bot token and app token swapped
- `~/.openclaw/.env` has both tokens on one malformed line
- Slack app was not reinstalled after scope changes

Check `.env` shape without printing token values:

```bash
grep -nE '^SLACK_(APP|BOT)_TOKEN=' ~/.openclaw/.env | sed 's/=.*/=<redacted>/'
```

Expected:

- exactly one `SLACK_APP_TOKEN=<redacted>` line
- exactly one `SLACK_BOT_TOKEN=<redacted>` line
- no literal `nSLACK_BOT_TOKEN` text appended to the app-token line

Re-run the direct Slack API checks from section 11. Both calls must return `"ok":true`.

### Symptom: Slack dependency install fails with `ENOTEMPTY`

Cause:

- stale or partially installed OpenClaw plugin runtime dependency directory

Fix:

```bash
TS=$(date +%Y%m%d-%H%M%S)
mv ~/.openclaw/plugin-runtime-deps ~/.openclaw/plugin-runtime-deps.bak-$TS
systemctl --user restart openclaw-gateway
journalctl --user -u openclaw-gateway.service -n 120 --no-pager | grep -i slack
```

Expected:

- OpenClaw reinstalls bundled Slack runtime dependencies
- logs show `[slack] socket mode connected`

### Symptom: `openclaw status` reports unresolved Slack env SecretRef

Example:

```text
unresolved SecretRef env:default:SLACK_BOT_TOKEN
```

This can appear from the CLI even while the gateway service has loaded the `.env` file correctly. Prefer these checks for operational verification:

```bash
openclaw gateway status
journalctl --user -u openclaw-gateway.service -n 120 --no-pager | grep -i slack
```

Expected:

- gateway connectivity probe is `ok`
- Slack logs show Socket Mode connected

### Symptom: Slack answer starts then stalls, or replies are very slow

Observed evidence from the recorded run:

- gateway process used sustained high CPU on `t4g.medium`
- bundled runtime dependency install ran during gateway restart
- logs showed `event_loop_delay` warnings with max delay over 30 seconds
- `sessions.list` took about 47 seconds
- Slack Socket Mode emitted ping/pong timeout warnings and briefly disconnected

Immediate mitigations:

```bash
sudo -iu ubuntu
grep -nE 'gpt-5\.[34]|primary|openai-codex' ~/.openclaw/openclaw.json
systemctl --user restart openclaw-gateway
journalctl --user -u openclaw-gateway.service -n 120 --no-pager
```

Operational fixes:

- use `openai-codex/gpt-5.3` instead of `openai-codex/gpt-5.4`
- avoid repeated gateway restarts while bundled runtime dependencies are installing
- use at least `c7g.large` for Slack Socket Mode plus OpenClaw gateway
- if plugin runtime dependencies are repeatedly reinstalled or missing packages such as `ajv`/`sqlite-vec`, rebuild `~/.openclaw/plugin-runtime-deps` during a maintenance window

Recorded command used to switch the running instance to `gpt-5.3`:

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak-model-$(date +%Y%m%d-%H%M%S)
sed -i 's/openai-codex\/gpt-5\.4/openai-codex\/gpt-5.3/g; s/"id": "gpt-5\.4"/"id": "gpt-5.3"/g' ~/.openclaw/openclaw.json
systemctl --user restart openclaw-gateway.service
journalctl --user -u openclaw-gateway.service -n 120 --no-pager | grep 'agent model'
```

Expected:

```text
[gateway] agent model: openai-codex/gpt-5.3
```

## 14. Post-Run State From The Recorded Execution

Recorded deployment result:

- deleted stack: `openclaw-bedrock`
- created stack: `openclaw-oauth`
- region: `us-east-1`
- instance id: `i-02a5490be86c44b61`
- instance type at deployment time: `t4g.medium`
- retained data volume enabled
- gateway verified healthy through SSM-only access
- OpenAI OAuth completed with provider `openai-codex`
- primary model verified as `openai-codex/gpt-5.3`
- Slack Socket Mode connected
- Slack sender pairing approved for user id `U0545CGCCQ0`
- performance issue observed on `t4g.medium`; future deployments should use `c7g.large` or larger

Security follow-up:

- Rotate Slack tokens if they were pasted into chat, screenshots, shell history, tickets, or any other shared surface.

## 15. OpenTofu Migration

New infrastructure work should use OpenTofu instead of Terraform or raw CloudFormation.

OpenTofu stack path:

```text
opentofu/openclaw-private
```

Validate locally:

```bash
cd opentofu/openclaw-private
tofu init -backend=false
tofu validate
```

Current scope:

- private SSM-only OpenClaw deployment
- no public ALB, CloudFront, or WAF
- OpenAI OAuth provider `openai-codex`
- default model `gpt-5.3`
- default instance type `c7g.large`
- Slack Socket Mode supported by outbound internet access

Do not run `tofu apply` against names already owned by the current CloudFormation stack until one of these is true:

- the CloudFormation stack has been destroyed intentionally
- existing AWS resources have been imported into OpenTofu state

## 16. Follow-Up Maintenance

If `clawdbot-bedrock.yaml` changes again, re-upload it:

```bash
aws s3api put-object \
  --profile aws-dimly \
  --region us-east-1 \
  --bucket openclaw-cfn-templates-831597648506-us-east-1 \
  --key openclaw-oauth/clawdbot-bedrock.yaml \
  --body clawdbot-bedrock.yaml \
  --server-side-encryption AES256
```

Then re-run:

```bash
aws cloudformation validate-template \
  --profile aws-dimly \
  --region us-east-1 \
  --template-url \
  https://openclaw-cfn-templates-831597648506-us-east-1.s3.us-east-1.amazonaws.com/openclaw-oauth/clawdbot-bedrock.yaml
```
