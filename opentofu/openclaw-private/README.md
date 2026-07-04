# OpenClaw Private OpenTofu Deployment

This OpenTofu stack deploys the private SSM-only OpenClaw path used for the OAuth + Slack Socket Mode runbook.

It intentionally does not create public ALB, CloudFront, or WAF resources. Gateway access is through SSM port forwarding only, and Slack uses outbound Socket Mode.

## Defaults

- Region: `us-east-1`
- AWS profile: `aws-dimly`
- Name: `openclaw-oauth`
- Instance type: `c7g.large`
- OpenClaw version: `2026.4.27`
- OpenAI model: `gpt-5.3`
- Public inbound access: none

## Deploy

```bash
tofu init
tofu plan
tofu apply
```

After apply:

```bash
tofu output -raw port_forward_command
tofu output -raw gateway_token_command
tofu output -raw openai_oauth_commands
```

## Existing CloudFormation Stack

The current `openclaw-oauth` stack was created by CloudFormation. Do not run `tofu apply` against the same resource names until you either:

1. destroy the CloudFormation stack and recreate with OpenTofu, or
2. import the existing AWS resources into OpenTofu state.

For this migration, the cleaner operational path is:

1. keep the current CloudFormation stack running
2. create an OpenTofu state backend
3. import VPC, subnet, route table, security group, IAM role/profile, instance, data volume, S3 bucket, SSM parameter, and alarms
4. run `tofu plan` until it is no-op or only intentional drift remains

Because the existing instance was bootstrapped by CloudFormation `cfn-init`, expect user-data drift on first import. Avoid replacing the instance until data has been backed up or the EBS data volume has been deliberately reattached.
