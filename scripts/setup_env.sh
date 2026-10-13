#!/usr/bin/env bash
# Sets up the main AWS test environment for the project.
# Run inside AWS CloudShell, from the project folder:
#   export ALERT_EMAIL=you@example.com
#   bash scripts/setup_env.sh
# It keeps going if one step fails, and prints a summary at the end.

set -u
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}}"
: "${ALERT_EMAIL:?Please run first: export ALERT_EMAIL=your@email.com}"
export AWS_DEFAULT_REGION="$REGION"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || exit 1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TRAIL_BUCKET="cloudposture-trail-logs-$ACCOUNT_ID"
CONFIG_BUCKET="cloudposture-config-$ACCOUNT_ID"
TEST_BUCKET="cloudposture-test-public-$ACCOUNT_ID"
FAILED=()

say() { echo; echo "=== $1"; }
ok()  { echo "   ok: $1"; }
bad() { echo "   [!] problem with: $1"; FAILED+=("$1"); }

mkbucket() {
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$1" >/dev/null
  else
    aws s3api create-bucket --bucket "$1" --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
}

echo "Account: $ACCOUNT_ID   Region: $REGION"

# 1. Budget alert
say "1. Billing budget alert"
aws budgets create-budget --account-id "$ACCOUNT_ID" \
  --budget '{"BudgetName":"project-monthly-budget","BudgetLimit":{"Amount":"10","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers "[{\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":80,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"$ALERT_EMAIL\"}]}]" \
  && ok "budget created" || bad "budget"

# 2. Read-only collector role
say "2. Read-only collector role"
aws iam create-policy --policy-name CloudPostureCollectorPolicy \
  --policy-document "file://$SCRIPT_DIR/collector_policy.json" >/dev/null && ok "policy created" || bad "collector policy"
cat > /tmp/trust.json << EOT
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::$ACCOUNT_ID:root"},"Action":"sts:AssumeRole"}]}
EOT
aws iam create-role --role-name CloudPostureCollectorRole \
  --assume-role-policy-document file:///tmp/trust.json >/dev/null && ok "role created" || bad "collector role"
aws iam attach-role-policy --role-name CloudPostureCollectorRole \
  --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/CloudPostureCollectorPolicy" && ok "policy attached" || bad "attach collector policy"

# 3. CloudTrail
say "3. CloudTrail (multi-region trail)"
mkbucket "$TRAIL_BUCKET" && ok "trail bucket" || bad "trail bucket"
cat > /tmp/trail_policy.json << EOT
{"Version":"2012-10-17","Statement":[
{"Sid":"AWSCloudTrailAclCheck","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},"Action":"s3:GetBucketAcl","Resource":"arn:aws:s3:::$TRAIL_BUCKET"},
{"Sid":"AWSCloudTrailWrite","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::$TRAIL_BUCKET/AWSLogs/$ACCOUNT_ID/*","Condition":{"StringEquals":{"s3:x-amz-acl":"bucket-owner-full-control"}}}]}
EOT
aws s3api put-bucket-policy --bucket "$TRAIL_BUCKET" --policy file:///tmp/trail_policy.json && ok "trail bucket policy" || bad "trail bucket policy"
aws cloudtrail create-trail --name cloudposture-trail --s3-bucket-name "$TRAIL_BUCKET" \
  --is-multi-region-trail --include-global-service-events >/dev/null && ok "trail created" || bad "create trail"
aws cloudtrail start-logging --name cloudposture-trail && ok "trail logging started" || bad "start logging"

# 4. IAM Access Analyzer
say "4. IAM Access Analyzer"
aws accessanalyzer create-analyzer --analyzer-name cloudposture-analyzer --type ACCOUNT >/dev/null \
  && ok "analyzer created" || bad "access analyzer"

# 5. AWS Config (needed by Security Hub controls) and Security Hub
say "5. AWS Config and Security Hub"
aws iam create-service-linked-role --aws-service-name config.amazonaws.com >/dev/null 2>&1 || true
mkbucket "$CONFIG_BUCKET" && ok "config bucket" || bad "config bucket"
cat > /tmp/config_policy.json << EOT
{"Version":"2012-10-17","Statement":[
{"Sid":"AWSConfigBucketPermissionsCheck","Effect":"Allow","Principal":{"Service":"config.amazonaws.com"},"Action":"s3:GetBucketAcl","Resource":"arn:aws:s3:::$CONFIG_BUCKET"},
{"Sid":"AWSConfigBucketExistenceCheck","Effect":"Allow","Principal":{"Service":"config.amazonaws.com"},"Action":"s3:ListBucket","Resource":"arn:aws:s3:::$CONFIG_BUCKET"},
{"Sid":"AWSConfigBucketDelivery","Effect":"Allow","Principal":{"Service":"config.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::$CONFIG_BUCKET/AWSLogs/$ACCOUNT_ID/Config/*","Condition":{"StringEquals":{"s3:x-amz-acl":"bucket-owner-full-control"}}}]}
EOT
aws s3api put-bucket-policy --bucket "$CONFIG_BUCKET" --policy file:///tmp/config_policy.json && ok "config bucket policy" || bad "config bucket policy"
aws configservice put-configuration-recorder \
  --configuration-recorder "name=default,roleARN=arn:aws:iam::$ACCOUNT_ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig" \
  --recording-group allSupported=true,includeGlobalResourceTypes=true && ok "config recorder" || bad "config recorder"
aws configservice put-delivery-channel \
  --delivery-channel "name=default,s3BucketName=$CONFIG_BUCKET" && ok "config delivery channel" || bad "config delivery channel"
aws configservice start-configuration-recorder --configuration-recorder-name default && ok "config recording started" || bad "start config recorder"
aws securityhub enable-security-hub --enable-default-standards && ok "security hub enabled" || bad "security hub"

# 6. Deliberately misconfigured test resources (no real data anywhere)
say "6. Test resources with deliberate misconfigurations"

# 6a. Public S3 bucket
mkbucket "$TEST_BUCKET" && ok "test bucket" || bad "test bucket"
aws s3control put-public-access-block --account-id "$ACCOUNT_ID" \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false \
  && ok "account public access block off" || bad "account public access block"
aws s3api put-public-access-block --bucket "$TEST_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false \
  && ok "bucket public access block off" || bad "bucket public access block"
cat > /tmp/public_policy.json << EOT
{"Version":"2012-10-17","Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::$TEST_BUCKET/*"}]}
EOT
aws s3api put-bucket-policy --bucket "$TEST_BUCKET" --policy file:///tmp/public_policy.json && ok "public bucket policy" || bad "public bucket policy"
echo "dummy test file, no real data" > /tmp/dummy.txt
aws s3 cp /tmp/dummy.txt "s3://$TEST_BUCKET/dummy.txt" >/dev/null && ok "dummy file uploaded" || bad "dummy upload"

# 6b. Overly permissive IAM policy, on a role that trusts an outside account
aws iam create-policy --policy-name test-admin-star-policy \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' >/dev/null \
  && ok "admin-star policy" || bad "admin-star policy"
cat > /tmp/external_trust.json << EOT
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::111122223333:root"},"Action":"sts:AssumeRole"}]}
EOT
aws iam create-role --role-name test-overly-permissive-role \
  --assume-role-policy-document file:///tmp/external_trust.json >/dev/null && ok "external-trust role" || bad "external-trust role"
aws iam attach-role-policy --role-name test-overly-permissive-role \
  --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/test-admin-star-policy" && ok "policy attached to test role" || bad "attach test policy"

# 6c. Security group open to the internet on SSH
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  SG_ID=$(aws ec2 create-security-group --group-name test-open-ssh-sg --description "test: open SSH" --vpc-id "$VPC_ID" --query GroupId --output text) && ok "security group $SG_ID" || bad "security group"
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null && ok "SSH open to 0.0.0.0/0" || bad "open SSH rule"
else
  echo "   no default VPC in $REGION, skipping the security group"
fi

# 6d. IAM user with an access key that is never used
aws iam create-user --user-name test-unused-user >/dev/null && ok "unused user" || bad "unused user"
aws iam create-access-key --user-name test-unused-user --query 'AccessKey.AccessKeyId' --output text >/dev/null \
  && ok "unused access key created (secret discarded)" || bad "unused access key"

# 7. Some CloudTrail activity, including a failed call
say "7. Generating a little CloudTrail activity"
aws iam get-user --user-name this-user-does-not-exist >/dev/null 2>&1 || true
aws s3 ls >/dev/null 2>&1 || true

echo
echo "=============================================="
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "Setup finished with no problems."
else
  echo "Setup finished, but these steps had problems:"
  for f in "${FAILED[@]}"; do echo "  - $f"; done
  echo "Copy the red/[!] lines above and send them to Claude."
fi
echo "Wait 15 to 30 minutes, then run: bash scripts/verify_env.sh"
