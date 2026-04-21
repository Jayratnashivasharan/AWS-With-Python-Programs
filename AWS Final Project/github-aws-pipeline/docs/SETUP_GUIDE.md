# GitHub → AWS CodeDeploy Pipeline — Complete Setup Guide

> **Stack**: Node.js · Docker · Amazon ECR · CodeBuild · CodeDeploy · CodePipeline · EC2

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Project Structure](#2-project-structure)
3. [IAM Roles & Permissions](#3-iam-roles--permissions)
4. [Create ECR Repository](#4-create-ecr-repository)
5. [Launch & Configure EC2 Instance](#5-launch--configure-ec2-instance)
6. [Install Docker & CodeDeploy Agent on EC2](#6-install-docker--codedeploy-agent-on-ec2)
7. [Configure CodeDeploy](#7-configure-codedeploy)
8. [Configure CodeBuild](#8-configure-codebuild)
9. [Configure CodePipeline](#9-configure-codepipeline)
10. [Connect GitHub Repository](#10-connect-github-repository)
11. [Test Locally with Docker](#11-test-locally-with-docker)
12. [Test on AWS](#12-test-on-aws)
13. [CloudWatch Monitoring](#13-cloudwatch-monitoring)
14. [Load Balancer Setup (Bonus)](#14-load-balancer-setup-bonus)
15. [Troubleshooting](#15-troubleshooting)
16. [All Commands Reference](#16-all-commands-reference)

---

## 1. Prerequisites

### Tools Required (on your local machine)

```bash
# Verify these are installed:
git --version          # Git 2.x+
docker --version       # Docker 20+
aws --version          # AWS CLI v2
node --version         # Node.js 18+
npm --version          # npm 9+
```

### Install AWS CLI v2

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Configure
aws configure
# AWS Access Key ID:     [your-key-id]
# AWS Secret Access Key: [your-secret]
# Default region:        us-east-1
# Default output format: json
```

---

## 2. Project Structure

```
github-aws-pipeline/
├── app/
│   ├── src/
│   │   ├── server.js              # Express app entry point
│   │   ├── config/
│   │   │   └── app.js             # App configuration
│   │   ├── routes/
│   │   │   ├── api.js             # API endpoints
│   │   │   └── health.js          # Health check endpoints
│   │   └── middleware/
│   │       ├── errorHandler.js    # Centralized error handler
│   │       └── requestLogger.js   # Request logging
│   ├── public/
│   │   ├── index.html             # Dashboard UI
│   │   ├── css/style.css
│   │   └── js/app.js
│   └── package.json
├── aws/
│   ├── scripts/
│   │   ├── stop.sh                # ApplicationStop hook
│   │   ├── install.sh             # BeforeInstall hook
│   │   ├── after_install.sh       # AfterInstall hook
│   │   ├── start.sh               # ApplicationStart hook
│   │   └── validate.sh            # ValidateService hook
│   └── nginx.conf                 # NGINX reverse proxy config
├── Dockerfile                     # Multi-stage production Dockerfile
├── .dockerignore
├── docker-compose.yml             # Local development stack
├── buildspec.yml                  # CodeBuild instructions
├── appspec.yml                    # CodeDeploy instructions
├── .env.example                   # Environment template
├── .gitignore
└── docs/
    └── SETUP_GUIDE.md             # This file
```

---

## 3. IAM Roles & Permissions

> ⚠️ **This is the most critical part.** Wrong IAM = nothing works.

### 3.1 EC2 Instance Role (attach to EC2)

**Role Name**: `EC2CodeDeployRole`  
**Trusted entity**: EC2

**Policies to attach**:

```json
// Policy 1: AmazonEC2RoleforAWSCodeDeploy (AWS Managed)
// Policy 2: AmazonEC2ContainerRegistryReadOnly (AWS Managed)
// Policy 3: CloudWatchAgentServerPolicy (AWS Managed)
// Policy 4: Custom inline policy below:
```

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:DescribeRepositories",
        "ecr:ListImages"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Sid": "SSMParameterStore",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/app/*"
    }
  ]
}
```

**CLI Commands**:

```bash
# Create EC2 trust policy
cat > /tmp/ec2-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name EC2CodeDeployRole \
  --assume-role-policy-document file:///tmp/ec2-trust-policy.json

# Attach managed policies
aws iam attach-role-policy \
  --role-name EC2CodeDeployRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy

aws iam attach-role-policy \
  --role-name EC2CodeDeployRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
  --role-name EC2CodeDeployRole \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name EC2CodeDeployRole

aws iam add-role-to-instance-profile \
  --instance-profile-name EC2CodeDeployRole \
  --role-name EC2CodeDeployRole
```

---

### 3.2 CodeDeploy Service Role

**Role Name**: `CodeDeployServiceRole`  
**Trusted entity**: CodeDeploy

```bash
# Trust policy for CodeDeploy
cat > /tmp/codedeploy-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "codedeploy.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name CodeDeployServiceRole \
  --assume-role-policy-document file:///tmp/codedeploy-trust-policy.json

aws iam attach-role-policy \
  --role-name CodeDeployServiceRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
```

---

### 3.3 CodeBuild Service Role

**Role Name**: `CodeBuildServiceRole`

```bash
cat > /tmp/codebuild-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "codebuild.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name CodeBuildServiceRole \
  --assume-role-policy-document file:///tmp/codebuild-trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name CodeBuildServiceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# Inline policy for S3, logs, CodePipeline artifacts
cat > /tmp/codebuild-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:GetBucketAcl", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::codepipeline-*", "arn:aws:s3:::codepipeline-*/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ],
      "Resource": "arn:aws:ecr:*:*:repository/*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name CodeBuildServiceRole \
  --policy-name CodeBuildInlinePolicy \
  --policy-document file:///tmp/codebuild-policy.json
```

---

### 3.4 CodePipeline Service Role

**Role Name**: `CodePipelineServiceRole`

```bash
cat > /tmp/codepipeline-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "codepipeline.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name CodePipelineServiceRole \
  --assume-role-policy-document file:///tmp/codepipeline-trust-policy.json

aws iam attach-role-policy \
  --role-name CodePipelineServiceRole \
  --policy-arn arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess

cat > /tmp/pipeline-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::codepipeline-*", "arn:aws:s3:::codepipeline-*/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["codebuild:BatchGetBuilds", "codebuild:StartBuild"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["codedeploy:*"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["codestar-connections:UseConnection"],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name CodePipelineServiceRole \
  --policy-name CodePipelineInlinePolicy \
  --policy-document file:///tmp/pipeline-policy.json
```

---

## 4. Create ECR Repository

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REPO_NAME=github-aws-pipeline

# Create the ECR repository
aws ecr create-repository \
  --repository-name $ECR_REPO_NAME \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256

echo "ECR URI: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

# Set lifecycle policy (keep only last 10 images)
aws ecr put-lifecycle-policy \
  --repository-name $ECR_REPO_NAME \
  --lifecycle-policy-text '{
    "rules": [
      {
        "rulePriority": 1,
        "description": "Keep last 10 images",
        "selection": {
          "tagStatus": "any",
          "countType": "imageCountMoreThan",
          "countNumber": 10
        },
        "action": { "type": "expire" }
      }
    ]
  }'
```

---

## 5. Launch & Configure EC2 Instance

### Via AWS Console

1. Go to **EC2 → Launch Instance**
2. Settings:
   - **Name**: `pipeline-demo-server`
   - **AMI**: Amazon Linux 2023 (or Ubuntu 22.04)
   - **Instance Type**: `t3.small` (minimum; `t3.medium` recommended)
   - **Key Pair**: Create or select an existing key pair
   - **Security Group**: Create new with these rules:
     - SSH (22) — your IP only
     - HTTP (80) — 0.0.0.0/0
     - HTTPS (443) — 0.0.0.0/0
     - Custom TCP (3000) — 0.0.0.0/0 (app port, optional)
   - **IAM Instance Profile**: `EC2CodeDeployRole`
   - **Storage**: 20 GB gp3

3. Add this **User Data** script (runs on first boot):

```bash
#!/bin/bash
yum update -y
yum install -y ruby wget curl

# Install CodeDeploy Agent
cd /home/ec2-user
wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
chmod +x ./install
./install auto

# Start CodeDeploy agent
systemctl start codedeploy-agent
systemctl enable codedeploy-agent

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

echo "Bootstrap complete!" > /tmp/bootstrap-done.txt
```

### Via AWS CLI

```bash
# Get latest Amazon Linux 2023 AMI
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters 'Name=name,Values=al2023-ami-*-kernel-*-x86_64' \
            'Name=state,Values=available' \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

echo "Using AMI: $AMI_ID"

# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name pipeline-demo-sg \
  --description "Security group for pipeline demo" \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3000 --cidr 0.0.0.0/0

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.small \
  --security-group-ids $SG_ID \
  --iam-instance-profile Name=EC2CodeDeployRole \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=pipeline-demo-server},{Key=Environment,Value=production}]' \
  --user-data file:///tmp/userdata.sh \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Public IP: $PUBLIC_IP"
echo "SSH: ssh -i your-key.pem ec2-user@$PUBLIC_IP"
```

---

## 6. Install Docker & CodeDeploy Agent on EC2

If not done via User Data, SSH in and run:

```bash
ssh -i your-key.pem ec2-user@YOUR_EC2_IP

# ─── Install CodeDeploy Agent ───────────────────────────────
sudo yum update -y
sudo yum install -y ruby wget
cd /home/ec2-user
wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo systemctl start codedeploy-agent
sudo systemctl enable codedeploy-agent

# Verify CodeDeploy agent is running
sudo systemctl status codedeploy-agent

# ─── Install Docker ─────────────────────────────────────────
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
newgrp docker

# Verify Docker
docker --version
docker run --rm hello-world

# ─── Install AWS CLI ────────────────────────────────────────
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
aws --version

# ─── Tag the instance (required for CodeDeploy targeting) ───
# This is done from your local machine:
aws ec2 create-tags \
  --resources $INSTANCE_ID \
  --tags Key=CodeDeploy,Value=true Key=Environment,Value=production
```

---

## 7. Configure CodeDeploy

```bash
# Create CodeDeploy Application
aws deploy create-application \
  --application-name github-aws-pipeline-app \
  --compute-platform Server

# Create Deployment Group
aws deploy create-deployment-group \
  --application-name github-aws-pipeline-app \
  --deployment-group-name github-aws-pipeline-group \
  --service-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/CodeDeployServiceRole \
  --deployment-config-name CodeDeployDefault.OneAtATime \
  --ec2-tag-filters Key=Name,Value=pipeline-demo-server,Type=KEY_AND_VALUE \
  --auto-rollback-configuration enabled=true,events=DEPLOYMENT_FAILURE \
  --deployment-style deploymentType=IN_PLACE,deploymentOption=WITHOUT_TRAFFIC_CONTROL
```

---

## 8. Configure CodeBuild

### Via AWS Console

1. Go to **CodeBuild → Create build project**
2. Settings:
   - **Project name**: `github-aws-pipeline-build`
   - **Source**: Connect to your GitHub repo (or use S3/CodePipeline)
   - **Environment**:
     - Managed image: Amazon Linux 2
     - Runtime: Standard
     - Image: `aws/codebuild/standard:7.0`
     - ✅ Privileged (REQUIRED for Docker builds)
   - **Service role**: `CodeBuildServiceRole`
   - **Buildspec**: Use a buildspec file → `buildspec.yml`
3. **Environment Variables** (add these):
   - `AWS_ACCOUNT_ID` = `123456789012` (your account)
   - `AWS_DEFAULT_REGION` = `us-east-1`
   - `ECR_REPOSITORY_NAME` = `github-aws-pipeline`

### Via AWS CLI

```bash
aws codebuild create-project \
  --name github-aws-pipeline-build \
  --source type=CODEPIPELINE,buildspec=buildspec.yml \
  --artifacts type=CODEPIPELINE \
  --environment '{
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_SMALL",
    "privilegedMode": true,
    "environmentVariables": [
      {"name": "AWS_ACCOUNT_ID", "value": "'$AWS_ACCOUNT_ID'", "type": "PLAINTEXT"},
      {"name": "AWS_DEFAULT_REGION", "value": "'$AWS_REGION'", "type": "PLAINTEXT"},
      {"name": "ECR_REPOSITORY_NAME", "value": "github-aws-pipeline", "type": "PLAINTEXT"}
    ]
  }' \
  --service-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/CodeBuildServiceRole
```

---

## 9. Configure CodePipeline

### Create S3 Bucket for artifacts

```bash
BUCKET_NAME="codepipeline-${AWS_REGION}-${AWS_ACCOUNT_ID}-pipeline"
aws s3 mb s3://${BUCKET_NAME} --region $AWS_REGION
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
```

### Create CodePipeline via Console

1. Go to **CodePipeline → Create pipeline**
2. **Pipeline settings**:
   - Name: `github-aws-codedeploy-pipeline`
   - Service role: `CodePipelineServiceRole`
   - Artifact store: S3 bucket created above

3. **Source Stage**:
   - Source provider: **GitHub (Version 2)**
   - Click "Connect to GitHub" → authorize OAuth
   - Repository: `your-username/your-repo`
   - Branch: `main`
   - Detection: GitHub webhooks (auto-trigger)

4. **Build Stage**:
   - Build provider: **AWS CodeBuild**
   - Project name: `github-aws-pipeline-build`

5. **Deploy Stage**:
   - Deploy provider: **AWS CodeDeploy**
   - Application name: `github-aws-pipeline-app`
   - Deployment group: `github-aws-pipeline-group`

### Create via CLI (complete pipeline JSON)

```bash
cat > /tmp/pipeline.json << EOF
{
  "pipeline": {
    "name": "github-aws-codedeploy-pipeline",
    "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/CodePipelineServiceRole",
    "artifactStore": {
      "type": "S3",
      "location": "${BUCKET_NAME}"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "GitHub_Source",
            "actionTypeId": {
              "category": "Source",
              "owner": "AWS",
              "provider": "CodeStarSourceConnection",
              "version": "1"
            },
            "configuration": {
              "ConnectionArn": "YOUR_CODESTAR_CONNECTION_ARN",
              "FullRepositoryId": "YOUR_GITHUB_USERNAME/YOUR_REPO_NAME",
              "BranchName": "main",
              "OutputArtifactFormat": "CODE_ZIP"
            },
            "outputArtifacts": [{"name": "SourceOutput"}]
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "CodeBuild",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "configuration": {
              "ProjectName": "github-aws-pipeline-build"
            },
            "inputArtifacts": [{"name": "SourceOutput"}],
            "outputArtifacts": [{"name": "BuildOutput"}]
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "CodeDeploy",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "CodeDeploy",
              "version": "1"
            },
            "configuration": {
              "ApplicationName": "github-aws-pipeline-app",
              "DeploymentGroupName": "github-aws-pipeline-group"
            },
            "inputArtifacts": [{"name": "BuildOutput"}]
          }
        ]
      }
    ]
  }
}
EOF

aws codepipeline create-pipeline --cli-input-json file:///tmp/pipeline.json
```

---

## 10. Connect GitHub Repository

```bash
# Step 1: Push your project to GitHub
cd github-aws-pipeline
git init
git add .
git commit -m "feat: initial production pipeline setup"
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main

# Step 2: Create GitHub connection in AWS Console
# Go to: Settings → Connections → Create connection → GitHub
# OR via CLI:
aws codestar-connections create-connection \
  --provider-type GitHub \
  --connection-name github-pipeline-connection

# Note the ConnectionArn from the output and use it in the pipeline config above
# Then complete the OAuth authorization in the AWS Console under Developer Tools → Connections
```

---

## 11. Test Locally with Docker

```bash
# Clone and enter project
cd github-aws-pipeline

# Copy env file
cp .env.example .env.local

# ─── Build Docker Image ────────────────────────────────────
docker build -t github-aws-pipeline-app:local .

# ─── Run Container ─────────────────────────────────────────
docker run -d \
  --name pipeline-app-test \
  -p 3000:3000 \
  --env-file .env.local \
  github-aws-pipeline-app:local

# ─── Test Endpoints ────────────────────────────────────────
curl http://localhost:3000/health
curl http://localhost:3000/health/detailed
curl http://localhost:3000/api/v1/
curl http://localhost:3000/api/v1/info
curl http://localhost:3000/api/v1/deployment
curl http://localhost:3000/api/v1/pipeline
curl http://localhost:3000/api/v1/metrics

# ─── Open Dashboard ────────────────────────────────────────
open http://localhost:3000

# ─── View Logs ─────────────────────────────────────────────
docker logs pipeline-app-test -f

# ─── Cleanup ───────────────────────────────────────────────
docker stop pipeline-app-test && docker rm pipeline-app-test

# ─── Run with Docker Compose (with NGINX) ──────────────────
docker-compose up --build
# Open http://localhost (port 80 via NGINX)
```

---

## 12. Test on AWS

### Verify Pipeline Execution

```bash
# Check pipeline status
aws codepipeline get-pipeline-state \
  --name github-aws-codedeploy-pipeline

# Check latest execution
aws codepipeline list-pipeline-executions \
  --pipeline-name github-aws-codedeploy-pipeline \
  --max-results 5

# Trigger pipeline manually
aws codepipeline start-pipeline-execution \
  --name github-aws-codedeploy-pipeline
```

### Verify Deployment on EC2

```bash
# SSH into EC2
ssh -i your-key.pem ec2-user@YOUR_EC2_IP

# Check running containers
docker ps

# Check container logs
docker logs github-aws-pipeline-app --tail 50 -f

# Check CodeDeploy agent logs
sudo tail -f /var/log/aws/codedeploy-agent/codedeploy-agent.log

# Check deployment script logs
cat /var/log/codedeploy-github-aws-pipeline-app.log

# Test health endpoint from EC2
curl http://localhost:80/health
```

### Test from Internet

```bash
# Replace with your EC2 public IP or domain
EC2_IP=YOUR_EC2_PUBLIC_IP

curl http://$EC2_IP/health
curl http://$EC2_IP/api/v1/info
curl http://$EC2_IP/health/detailed | python3 -m json.tool

# Open dashboard in browser
echo "Dashboard: http://$EC2_IP"
```

---

## 13. CloudWatch Monitoring

```bash
# Create log group for the app
aws logs create-log-group \
  --log-group-name /aws/ec2/github-aws-pipeline-app

# Set retention to 30 days
aws logs put-retention-policy \
  --log-group-name /aws/ec2/github-aws-pipeline-app \
  --retention-in-days 30

# Create CloudWatch alarm for CPU
aws cloudwatch put-metric-alarm \
  --alarm-name pipeline-app-high-cpu \
  --alarm-description "CPU usage above 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --alarm-actions YOUR_SNS_TOPIC_ARN

# Create CloudWatch Dashboard
aws cloudwatch put-dashboard \
  --dashboard-name PipelineAppDashboard \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "properties": {
          "title": "EC2 CPU Utilization",
          "metrics": [["AWS/EC2", "CPUUtilization", "InstanceId", "'$INSTANCE_ID'"]],
          "period": 300,
          "stat": "Average",
          "view": "timeSeries"
        }
      }
    ]
  }'
```

---

## 14. Load Balancer Setup (Bonus)

```bash
# Create Application Load Balancer
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name pipeline-app-alb \
  --subnets subnet-xxx subnet-yyy \
  --security-groups $SG_ID \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# Create Target Group
TG_ARN=$(aws elbv2 create-target-group \
  --name pipeline-app-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id YOUR_VPC_ID \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Register EC2 instance
aws elbv2 register-targets \
  --target-group-arn $TG_ARN \
  --targets Id=$INSTANCE_ID,Port=80

# Create HTTP Listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

echo "ALB DNS: $(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].DNSName' --output text)"
```

---

## 15. Troubleshooting

### CodeDeploy Agent Not Running

```bash
sudo systemctl status codedeploy-agent
sudo systemctl restart codedeploy-agent
sudo tail -200 /var/log/aws/codedeploy-agent/codedeploy-agent.log
```

### Docker ECR Auth Fails

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
# If this fails: check EC2 IAM role has AmazonEC2ContainerRegistryReadOnly
```

### Container Exits Immediately

```bash
docker logs github-aws-pipeline-app
# Common cause: missing .env file or wrong ENV variable
# Fix: check /opt/app/.env exists on EC2
```

### Port 80 Not Accessible

```bash
# Check security group allows port 80
aws ec2 describe-security-groups --group-ids $SG_ID
# Check NGINX or app is actually listening
sudo netstat -tlnp | grep :80
```

### Build Fails — Docker Not Privileged

```
Error: Cannot connect to the Docker daemon
Fix: In CodeBuild project, enable "Privileged" mode
```

### Deployment Rollback Happens

```bash
# Check deployment details
aws deploy get-deployment --deployment-id d-XXXXXXXXX

# Check instance deployment logs
aws deploy get-deployment-instance \
  --deployment-id d-XXXXXXXXX \
  --instance-id i-XXXXXXXXX
```

---

## 16. All Commands Reference

```bash
# ─── Git Commands ──────────────────────────────────────────
git init
git add .
git commit -m "your message"
git push origin main

# ─── Docker Commands ───────────────────────────────────────
docker build -t myapp:latest .
docker run -d -p 3000:3000 --name myapp myapp:latest
docker logs myapp -f
docker stop myapp && docker rm myapp
docker system prune -f

# ─── ECR Push ──────────────────────────────────────────────
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
docker tag myapp:latest ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/github-aws-pipeline:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/github-aws-pipeline:latest

# ─── Pipeline Commands ─────────────────────────────────────
aws codepipeline start-pipeline-execution --name github-aws-codedeploy-pipeline
aws codepipeline get-pipeline-state --name github-aws-codedeploy-pipeline
aws codepipeline list-pipeline-executions --pipeline-name github-aws-codedeploy-pipeline

# ─── CodeDeploy Commands ───────────────────────────────────
aws deploy list-deployments --application-name github-aws-pipeline-app
aws deploy get-deployment --deployment-id d-XXXXXXXXX
aws deploy list-deployment-instances --deployment-id d-XXXXXXXXX

# ─── EC2 Commands ──────────────────────────────────────────
aws ec2 describe-instances --filters "Name=tag:Name,Values=pipeline-demo-server"
aws ec2 start-instances --instance-ids $INSTANCE_ID
aws ec2 stop-instances --instance-ids $INSTANCE_ID
```
