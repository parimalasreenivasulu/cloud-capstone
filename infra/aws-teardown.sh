#!/usr/bin/env bash
# Usage: ./infra/aws-teardown.sh <instance-id> <sg-id> <allocation-id> [region]
set -euo pipefail
export AWS_DEFAULT_REGION="${4:-ap-south-1}"
aws ec2 terminate-instances --instance-ids "$1" >/dev/null
aws ec2 wait instance-terminated --instance-ids "$1"
aws ec2 release-address --allocation-id "$3"
aws ec2 delete-security-group --group-id "$2"
echo "Resources removed."
