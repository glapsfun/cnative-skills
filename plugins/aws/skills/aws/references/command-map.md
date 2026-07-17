# Command Map

Route from task to service command group, then confirm exact parameters with `aws <service> <command> help`. Everything below is v2 syntax.

## Identity and account

- Who am I / which account: `aws sts get-caller-identity`
- Assume a role ad hoc: `aws sts assume-role --role-arn … --role-session-name …`
- IAM inspection: `aws iam list-users|list-roles|get-role|list-attached-role-policies|get-policy-version`
- IAM changes (propose first): `aws iam create-role|put-role-policy|attach-role-policy|create-policy`
- Simulate permissions: `aws iam simulate-principal-policy`

## Compute (EC2)

- Inventory: `aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"` (heavily nested — query via `Reservations[].Instances[]`)
- Lifecycle: `aws ec2 start-instances|stop-instances|terminate-instances --instance-ids …` (all support `--dry-run`; terminate is irreversible)
- Launch: `aws ec2 run-instances` (use `--generate-cli-skeleton`), AMI lookup: `describe-images --owners amazon --filters …` + `sort_by(Images,&CreationDate)`
- Networking: `describe-security-groups|describe-subnets|describe-vpcs`, `authorize-security-group-ingress`
- Waiters: `aws ec2 wait instance-running|instance-stopped|instance-terminated`

## Storage (S3)

- Day-to-day objects: `aws s3 ls|cp|mv|rm|sync|presign` (high-level; `--recursive`, `--exclude`/`--include`, sync `--delete` + `--dryrun`, stream with `-`)
- Buckets: `aws s3 mb|rb` (`rb --force` empties first — destructive)
- Exact API/JSON: `aws s3api head-object|list-objects-v2|get-bucket-policy|put-bucket-versioning|abort-multipart-upload`
- Account-level controls: `aws s3control`

## Serverless and containers

- Lambda: `aws lambda list-functions|get-function|invoke out.json --cli-binary-format raw-in-base64-out --payload '{"k":"v"}'|update-function-code`
- ECR login: `aws ecr get-login-password | docker login --username AWS --password-stdin <acct>.dkr.ecr.<region>.amazonaws.com`
- ECS: `aws ecs list-clusters|list-services|describe-services|update-service --force-new-deployment|execute-command`
- EKS: `aws eks list-clusters|describe-cluster`, kubeconfig: `aws eks update-kubeconfig --name <cluster> --region <region>`

## Infrastructure as code (CloudFormation)

- Deploy: `aws cloudformation deploy --template-file t.yaml --stack-name s --capabilities CAPABILITY_NAMED_IAM` (empty changeset = exit 0 in v2)
- Inspect: `describe-stacks|describe-stack-events|list-stack-resources`, drift: `detect-stack-drift`
- Waiters: `aws cloudformation wait stack-create-complete|stack-update-complete|stack-delete-complete`

## Observability (CloudWatch)

- Tail logs live: `aws logs tail /my/group --follow --since 1h` (v2 custom command)
- Search: `aws logs filter-log-events --log-group-name … --filter-pattern …`, Insights: `start-query`/`get-query-results`
- Metrics/alarms: `aws cloudwatch get-metric-statistics|describe-alarms`

## Config, secrets, parameters

- SSM parameters: `aws ssm get-parameter --name … --with-decryption`, `put-parameter`
- Secrets Manager: `aws secretsmanager get-secret-value --secret-id …` (never echo the output into logs)
- SSM sessions (no SSH): `aws ssm start-session --target i-…`

## Data

- DynamoDB: `aws dynamodb get-item|put-item|query|scan --filter-expression …`; v2 high-level: `aws ddb put|select`
- RDS: `aws rds describe-db-instances --filters …`, snapshots: `create-db-snapshot` + `aws rds wait db-snapshot-available`

## Discovering commands

- `aws help` (services), `aws <service> help` (commands), `aws <service> <command> help` (parameters + examples)
- Auto-prompt exploration: `aws --cli-auto-prompt` (fuzzy-completes services, commands, params; F5 previews output)
- Full reference: <https://docs.aws.amazon.com/cli/latest/reference/> — one page per command, generated from the live API model, so it always matches the current release.
