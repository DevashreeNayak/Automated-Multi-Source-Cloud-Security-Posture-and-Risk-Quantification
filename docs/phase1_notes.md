# Phase 1 setup notes (Devashree)

Fill this in as you go. It becomes part of the Phase 1 report.

- AWS account created (Free plan, new AWS experience), advanced features activated
- Region used: ap-southeast-2 (the region the console was already in)
- Budget alert created
- Collector role: CloudPostureCollectorRole
- CloudTrail trail: cloudposture-trail
- Access Analyzer: cloudposture-analyzer
- Config and Security Hub enabled
- Test resources: public S3 bucket, admin-star policy on an external-trust role, SSH open to the internet, unused IAM user with access key

Screenshots to take for the report:
1. Billing budget
2. CloudTrail trail status
3. Access Analyzer findings list
4. Security Hub findings summary
5. Output of scripts/verify_env.sh
