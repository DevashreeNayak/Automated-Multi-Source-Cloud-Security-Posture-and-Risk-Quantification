# Automated Multi-Source Cloud Security Posture and Risk Quantification

M.Sc. Cybersecurity, Semester III, Cloud Security and Forensics, NFSU Gandhinagar.

This project collects security and operational data from AWS (CloudTrail, IAM Access Analyzer, Security Hub), converts it into one common format, and calculates measurable metrics and an explainable risk score.

## Team

| Name | Enrollment No. | Phase 1 work |
|---|---|---|
| Devashree | 250103002030 | AWS setup, repository, combining everyone's work |
| Vidita | 250103002019 | CloudTrail collector |
| Nancy | 250103002046 | IAM Access Analyzer collector |
| Aishwariya | 250103002011 | Security Hub collector |
| Tanushree | 250103002006 | Common schema design |

## Folder structure

```
collectors/cloudtrail/        CloudTrail collector (Vidita)
collectors/access_analyzer/   Access Analyzer collector (Nancy)
collectors/security_hub/      Security Hub collector (Aishwariya)
schema/                       Common finding schema (Tanushree)
data/raw/                     Raw output, stays on your own machine (git ignored)
data/samples/                 Cleaned sample outputs that are safe to share
docs/                         Architecture diagram and notes
scripts/                      Environment setup scripts (Devashree)
```

## Rules

- Never commit access keys, secret keys, passwords or the .env file.
- Remove account IDs and other sensitive values from any sample before putting it in `data/samples/`.
- Each collector needs a README that says how to run it, and should save raw JSON.

## Setup

```
pip install -r requirements.txt
```

Python with boto3 is used for all collectors.
