#!/usr/bin/env bash
# Checks that each source is running and has data. Run in CloudShell.
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}}"
export AWS_DEFAULT_REGION="$REGION"

echo "--- CloudTrail logging?"
aws cloudtrail get-trail-status --name cloudposture-trail --query IsLogging --output text
echo "--- CloudTrail recent events (count)"
aws cloudtrail lookup-events --max-results 50 --query 'length(Events)' --output text

echo "--- Access Analyzer"
ARN=$(aws accessanalyzer list-analyzers --query 'analyzers[0].arn' --output text)
echo "$ARN"
echo "findings:"
aws accessanalyzer list-findings --analyzer-arn "$ARN" --query 'length(findings)' --output text

echo "--- AWS Config recorder"
aws configservice describe-configuration-recorder-status --query 'ConfigurationRecordersStatus[0].recording' --output text

echo "--- Security Hub"
aws securityhub describe-hub --query HubArn --output text
echo "findings (up to 1000):"
aws securityhub get-findings --max-items 1000 --query 'length(Findings)' --output text
