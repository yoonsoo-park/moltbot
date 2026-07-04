# Context Transfer: Bedrock to OpenAI API Migration

## User Request

The user wants to move this AWS OpenClaw deployment away from Amazon Bedrock/Nova models and use the OpenAI API instead. The user is switching to CLI mode because they want better visibility into changes.

Korean original intent:

> 현재 이 프로젝트는 moltbot를 aws nova 모델을 bedrock를 통해서 사용하고 있어. 이걸 openAPI api로 바꾸고 싶어.

I interpreted "openAPI api" as "OpenAI API".

## Files Modified So Far

- `clawdbot-bedrock.yaml`
- `clawdbot-bedrock-mac.yaml`

No docs other than this transfer note were intentionally updated yet.

There is also an untracked `AGENTS.md` in the repo. I did not create or modify it during this work.

## High-Level Change Direction

The current in-progress implementation changes the CloudFormation templates from Bedrock provider configuration to an OpenAI-compatible provider configuration used by the existing `clawdbot-china.yaml` pattern:

- Provider name: `openai`
- API type: `openai-completions`
- Auth: `api-key`
- Base URL parameter: `OpenAIApiBaseUrl`, default `https://api.openai.com/v1`
- Model parameter: `OpenAIModel`, default currently set to `gpt-5.5`
- API key parameter: `OpenAIApiKey`, `NoEcho: true`

The China template already uses this OpenAI-compatible config shape under provider `maas`; that was used as the local precedent.

## What Was Changed In `clawdbot-bedrock.yaml`

- Template description changed from Bedrock to OpenAI API.
- Replaced `OpenClawModel` parameter with:
  - `OpenAIModel`
  - `OpenAIApiKey`
  - `OpenAIApiBaseUrl`
- Updated `CreateVPCEndpoints` description to clarify that endpoints are for AWS management services, not OpenAI API traffic.
- Removed Bedrock Mantle region conditions and `CreateMantleEndpoint`.
- Removed Bedrock Runtime and Bedrock Mantle VPC endpoints.
- Removed IAM inline policies:
  - `BedrockAccessPolicy`
  - `BedrockMantleAccessPolicy`
- Updated both embedded OpenClaw config templates:
  - `/opt/openclaw/openclaw-config-legacy.json`
  - `/opt/openclaw/openclaw-config-modern.json`
- The modern config was changed from `plugins.entries.amazon-bedrock` auto-discovery to explicit `models.providers.openai`.
- Changed `agents.defaults.model.primary` from `amazon-bedrock/MODEL_ID_PLACEHOLDER` to `openai/MODEL_ID_PLACEHOLDER`.
- Removed Bedrock memory search config using Titan embeddings.
- Updated `SOUL.md` text to say OpenAI API instead of Bedrock.
- Updated bootstrap environment:
  - Adds `OPENAI_API_KEY`
  - Adds `OPENAI_BASE_URL`
  - Sets `OPENCLAW_MODEL=${OpenAIModel}`
  - Sets `OPENCLAW_LLM_PROVIDER=openai`
  - Removes `OPENCLAW_USE_BEDROCK=true`
- Updated `~/.openclaw/.env` generation for OpenAI API auth.
- Updated placeholder replacement to fill:
  - `OPENAI_API_BASE_URL_PLACEHOLDER`
  - `OPENAI_API_KEY_PLACEHOLDER`
  - `MODEL_ID_PLACEHOLDER`
- Updated outputs:
  - `BedrockModel` renamed to `OpenAIModelInUse`
  - Cost text says OpenAI API is billed by OpenAI
  - VPC endpoint cost reduced from six interface endpoints to four interface endpoints.

## Important Incomplete/Risky Point In Linux Template

The user interrupted while I was changing how the Linux template passes the OpenAI API key.

Current state:

- `OpenAIApiKey` is still a CloudFormation `NoEcho` parameter.
- I started moving the key out of `AWS::CloudFormation::Init` metadata and into UserData:
  - UserData now writes `/etc/openclaw-secrets.env`
  - setup script sources that file
  - setup script uses `$OPENAI_API_KEY_VALUE`

This needs careful review because CloudFormation `NoEcho` does not necessarily protect secrets from every place they appear, especially if they are placed into UserData, instance files, logs, or generated config. The current state is not final security design.

Recommended safer next step:

- Prefer storing `OpenAIApiKey` in AWS SSM Parameter Store as a `SecureString` during deployment or accepting an existing SSM parameter name, then have the instance fetch it at runtime using its IAM role.
- Avoid embedding the raw API key in CloudFormation metadata or UserData if possible.
- If keeping the current approach temporarily, audit:
  - `/var/log/cloud-init-output.log`
  - `/var/lib/cloud/instance/user-data.txt`
  - `/var/log/openclaw-setup.log`
  - CloudFormation stack events/template metadata exposure

## What Was Changed In `clawdbot-bedrock-mac.yaml`

- Template description changed from Bedrock to OpenAI API.
- Replaced `OpenClawModel` parameter and Bedrock `AllowedValues` with:
  - `OpenAIModel`
  - `OpenAIApiKey`
  - `OpenAIApiBaseUrl`
- Updated `CreateVPCEndpoints` description.
- Removed Bedrock Mantle region conditions and `CreateMantleEndpoint`.
- Removed Bedrock Runtime and Bedrock Mantle VPC endpoints.
- Removed `BedrockAccessPolicy`.
- Updated generated `~/.openclaw/openclaw.json`:
  - provider `openai`
  - `baseUrl: OPENAI_API_BASE_URL_PLACEHOLDER`
  - `api: openai-completions`
  - `auth: api-key`
  - `apiKey: OPENAI_API_KEY_PLACEHOLDER`
  - `primary: openai/MODEL_ID_PLACEHOLDER`
- Added OpenAI env vars to `.zshrc`.
- Added OpenAI env vars to the launchd plist.
- Added OpenAI env vars to the messaging channel enablement script.
- Updated outputs:
  - `BedrockModel` renamed to `OpenAIModelInUse`
  - Cost text says OpenAI API is billed by OpenAI
  - VPC endpoint cost reduced from five endpoints to three endpoints.

## Verification Already Run

These checks were run before the interruption:

```bash
ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_file(f); puts "OK #{f}" }' clawdbot-bedrock.yaml clawdbot-bedrock-mac.yaml
```

Result:

```text
OK clawdbot-bedrock.yaml
OK clawdbot-bedrock-mac.yaml
```

Search for leftover Bedrock-specific references in the two templates was clean for the searched terms:

```bash
rg -n "OpenClawModel|CreateMantleEndpoint|BedrockRuntimeVPCEndpoint|BedrockMantleVPCEndpoint|BedrockAccessPolicy|BedrockMantleAccessPolicy|OPENCLAW_USE_BEDROCK|amazon-bedrock|bedrock-runtime|bedrock-mantle|Bedrock:" clawdbot-bedrock.yaml clawdbot-bedrock-mac.yaml
```

AWS validation was attempted but did not complete because local AWS credentials are not configured:

```text
Unable to locate credentials. You can configure credentials by running "aws login".
```

`cfn-lint` is not installed in the current environment.

## Things The Next Agent Should Review

1. Decide the API key handling strategy before proceeding.
   - Current work is functional-looking but likely not ideal from a secret-management perspective.
   - Strong recommendation: use SSM Parameter Store `SecureString` rather than embedding the key in UserData/metadata.

2. Confirm the OpenClaw provider config shape.
   - I used the existing `clawdbot-china.yaml` `openai-completions` shape as precedent.
   - Verify against the currently installed/target OpenClaw version if possible.

3. Reconsider the default model.
   - I set `OpenAIModel` default to `gpt-5.5`.
   - This was based on visible current Codex app model names and an attempted official docs check, but the docs lookup was not completed cleanly.
   - If you need strict public API correctness, verify current OpenAI model IDs from official OpenAI docs before keeping this default.

4. Update docs if continuing the migration.
   - README, DEPLOYMENT, SECURITY, TROUBLESHOOTING still heavily describe Bedrock/Nova.
   - The templates are changed, but docs are not.

5. Re-run validation after finishing:
   - YAML parse
   - `rg` for stale Bedrock references
   - `aws cloudformation validate-template --region <region> --template-body file://...`
   - `cfn-lint` if available

## Current Git State At Transfer Time

Expected `git status --short`:

```text
 M clawdbot-bedrock-mac.yaml
 M clawdbot-bedrock.yaml
?? AGENTS.md
?? CONTEXT_TRANSFER.md
```

Expected diff size before adding this document:

```text
clawdbot-bedrock-mac.yaml | 153 +++++++++++------------------------
clawdbot-bedrock.yaml     | 198 +++++++++++++++++-----------------------------
```

## Suggested CLI Continuation

Start with:

```bash
git diff -- clawdbot-bedrock.yaml clawdbot-bedrock-mac.yaml
rg -n "OpenClawModel|CreateMantleEndpoint|BedrockRuntimeVPCEndpoint|BedrockMantleVPCEndpoint|BedrockAccessPolicy|BedrockMantleAccessPolicy|OPENCLAW_USE_BEDROCK|amazon-bedrock|bedrock-runtime|bedrock-mantle|Bedrock:" clawdbot-bedrock.yaml clawdbot-bedrock-mac.yaml
```

Then either:

- finish the current direct-API-key approach for a quick prototype, or
- rework to use `OpenAIApiKeyParameterName` / SSM SecureString for a safer CloudFormation design.

