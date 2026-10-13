#!/usr/bin/env bash
# Removes ONLY the deliberately misconfigured test resources.
# Leaves CloudTrail, Config, Security Hub and Access Analyzer alone.
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}}"
export AWS_DEFAULT_REGION="$REGION"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TEST_BUCKET="cloudposture-test-public-$ACCOUNT_ID"

aws s3 rm "s3://$TEST_BUCKET" --recursive >/dev/null 2>&1
aws s3api delete-bucket --bucket "$TEST_BUCKET"

aws iam detach-role-policy --role-name test-overly-permissive-role --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/test-admin-star-policy"
aws iam delete-role --role-name test-overly-permissive-role
aws iam delete-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/test-admin-star-policy"

for k in $(aws iam list-access-keys --user-name test-unused-user --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  aws iam delete-access-key --user-name test-unused-user --access-key-id "$k"
done
aws iam delete-user --user-name test-unused-user

SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=test-open-ssh-sg --query 'SecurityGroups[0].GroupId' --output text)
[ -n "$SG_ID" ] && [ "$SG_ID" != "None" ] && aws ec2 delete-security-group --group-id "$SG_ID"
echo "Test resources removed."
