#!/usr/bin/env bash
# Launch the capstone VM on AWS EC2 with the AWS CLI.
# Prereqs: `aws configure` done; an SSH keypair on your machine (ssh-keygen -t ed25519).
# Usage: ./infra/aws-ec2-launch.sh [region] [path-to-public-key]
set -euo pipefail
REGION="${1:-ap-south-1}"
PUBKEY_FILE="${2:-$HOME/.ssh/id_ed25519.pub}"
NAME="cloud-capstone"
export AWS_DEFAULT_REGION="$REGION"

# Ubuntu 24.04 LTS AMI (resolved via Canonical's public SSM parameter)
AMI=$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value --output text)

VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
MYIP="$(curl -fsS https://checkip.amazonaws.com)/32"

# Security group = cloud firewall: 80/443 public, 22 only from your current IP
SG=$(aws ec2 create-security-group --group-name "$NAME-sg-$(date +%s)" \
      --description "$NAME" --vpc-id "$VPC" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22  --cidr "$MYIP"      >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 80  --cidr 0.0.0.0/0    >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 443 --cidr 0.0.0.0/0    >/dev/null

# Render cloud-init with your public key
USERDATA=$(mktemp)
sed "s|SSH_PUBLIC_KEY_PLACEHOLDER|$(cat "$PUBKEY_FILE")|" "$(dirname "$0")/cloud-init.yaml" > "$USERDATA"

# t3.small: 2 GB RAM is the practical minimum for app + Prometheus + Grafana
IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.small \
  --security-group-ids "$SG" --user-data "file://$USERDATA" \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3}' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids "$IID"

# Elastic IP so the public URL survives stop/start
ALLOC=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
aws ec2 associate-address --instance-id "$IID" --allocation-id "$ALLOC" >/dev/null
IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOC" --query 'Addresses[0].PublicIp' --output text)

cat <<OUT

Instance:   $IID
Public IP:  $IP
Wait ~2 minutes for cloud-init, then:  ssh deploy@$IP
Set GitHub secrets: SSH_HOST=$IP  SSH_USER=deploy  PUBLIC_URL=http://$IP
Teardown:   ./infra/aws-teardown.sh $IID $SG $ALLOC $REGION
OUT
