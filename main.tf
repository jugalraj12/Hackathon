##provider aws
provider "aws" {
  alias   = "source"
  region  = "${var.region}"
  profile = "<hackathon>"
}
variable "region" {
  description = "AWS Deployment region.."
  default = "us-east-1"
}

resource "aws_vpc" "hackathon" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "hackathon"
  }
}
variable "public_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}
 
variable "private_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_vpc.hackathon.id
  cidr_ipv4         = aws_vpc.hackathon.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv6" {
  security_group_id = aws_vpc.hackathon.id
  cidr_ipv6         = aws_vpc.hackathon.ipv6_cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_vpc.hackathon.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Step 1: Create an ECR repository
resource "aws_ecr_repository" "lambda_ecr_repo" {
  name                 = "lambda-docker-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "lifecycle_policy" {
  repository = aws_ecr_repository.lambda_ecr_repo
  policy     = <<EOF
{
    "rules": [
        {
          "rulePriority": 1,
          "description": "Expire tagged images and maintain last 10 latest images",
          "selection": {
              "tagStatus": "any",
              "countType": "imageCountMoreThan",
              "countNumber": 10
          },
          "action": {
              "type": "expire"
          }
      }
    ]
}
EOF
  depends_on = [aws_ecr_repository.lambda_ecr_repo]
}

resource "aws_ecr_repository_policy" "policy" {

  repository = aws_ecr_repository.lambda_ecr_repo

  policy     = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossAccountPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "*"
        ]
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ]
    }
    
  ]
}
EOF
  depends_on = [aws_ecr_repository.lambda_ecr_repo]

}

# Step 2: Lambda execution role
resource "aws_iam_role" "lambda_exec_role" {
  name = "docker_lambda_exec_role"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow"
      }
    ]
  })
}

# Attach necessary policies to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Introduce a delay (e.g., 60 seconds)
resource "time_sleep" "wait_for_deployment" {
  create_duration = "60s"                      # Set delay duration
}

# Step 3: Create the Lambda function using Docker image
resource "aws_lambda_function" "lambda_docker" {
  function_name = "lambda-docker"
  role          = aws_iam_role.lambda_exec_role.arn

  package_type = "Image"
  image_uri    = "${aws_ecr_repository.lambda_ecr_repo.repository_url}:latest"  # Update with your ECR image URL

  # Set Lambda timeout and memory size
  memory_size = 128
  timeout     = 30

  ephemeral_storage {
    size = 1024
  }

  # Environment variables (optional)
  environment {
    variables = {
      LOG_LEVEL = "INFO"
      PORT = 3000
    }
  }

  depends_on = [time_sleep.wait_for_deployment]
}

resource "aws_lambda_function_url" "lambda_url" {
  function_name      = aws_lambda_function.lambda_docker.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["*"]
  }
}