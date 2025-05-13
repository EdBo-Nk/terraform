terraform {
  backend "s3" {
    bucket = "terraform-state-eden-devops-test"
    key    = "state/state.tfstate"
    region = "us-east-2"
  }
}
provider "aws" {
  region = "us-east-2"
}

# === VPC and Networking ===
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-2a"
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-2b"
  tags = {
    Name = "public-subnet-2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-routing-table"
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_association_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "ecs_service_sg" {
  name        = "ecs-service-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-service-sg"
  }
}

# Security group for EC2 instances
resource "aws_security_group" "ecs_instance_sg" {
  name        = "ecs-instance-sg"
  description = "Security group for ECS EC2 instances"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_service_sg.id]
    description = "Allow traffic from ECS service security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-instance-sg"
  }
}

# === S3, SQS, SSM ===
resource "aws_s3_bucket" "email_storage_bucket" {
  bucket         = "eden-devops-s3"
  force_destroy  = true
  tags = {
    Name        = "Email Storage Bucket"
    Environment = "dev"
  }
}

resource "aws_sqs_queue" "email_queue" {
  name = "email-processing-queue"
  tags = {
    Environment = "dev"
  }
}

resource "aws_ssm_parameter" "sqs_queue_url_parameter" {
  name  = "sqs_queue_url_parameter"
  type  = "SecureString"
  value = aws_sqs_queue.email_queue.id
}

# === ECS Cluster ===
resource "aws_ecs_cluster" "devops_cluster" {
  name = "devops-cluster"
}

# === IAM Role for ECS Tasks ===
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Effect = "Allow",
      Sid = ""
    }]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Effect = "Allow",
      Sid = ""
    }]
  })
}

# IAM role for EC2 instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# IAM role policy attachments
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_admin_access" {
  name        = "ecs-admin-access"
  description = "Allow ECS tasks full administrative access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "*",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_admin_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_admin_access.arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_admin_access" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_admin_access.arn
}

# Policy attachment for EC2 instance role
resource "aws_iam_role_policy_attachment" "ecs_instance_role_attachment" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Create instance profile for EC2
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# === EC2 Configuration ===
# Get the latest ECS-optimized AMI
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# Launch template for EC2 instances (replaces launch configuration)
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "ecs-launch-template-"
  image_id      = data.aws_ssm_parameter.ecs_optimized_ami.value
  instance_type = "t2.micro"  # Free tier eligible
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
  
  vpc_security_group_ids = [aws_security_group.ecs_instance_sg.id]
  
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.devops_cluster.name} >> /etc/ecs/ecs.config
              EOF
  )
  
  tag_specifications {
    resource_type = "instance"
    
    tags = {
      Name = "ecs-instance"
    }
  }
}

# Auto scaling group for EC2 instances
resource "aws_autoscaling_group" "ecs_asg" {
  name                = "ecs-asg"
  min_size            = 2
  max_size            = 2
  desired_capacity    = 2
  
  vpc_zone_identifier = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id
  ]
  
  # Use launch template instead of launch configuration
  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }
  
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }
}

# ECS capacity provider
resource "aws_ecs_capacity_provider" "ec2_capacity_provider" {
  name = "ec2-capacity-provider"
  
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    
    managed_scaling {
      maximum_scaling_step_size = 1
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

# Associate capacity provider with cluster
resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name = aws_ecs_cluster.devops_cluster.name
  
  capacity_providers = [aws_ecs_capacity_provider.ec2_capacity_provider.name]
  
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_capacity_provider.name
    weight = 1
  }
}

# === ECS Task Definition ===
resource "aws_ecs_task_definition" "email_api_task" {
  family                   = "email-api-task"
  cpu                      = "128"
  memory                   = "256"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "email-api-container"
    image     = "640107381183.dkr.ecr.us-east-2.amazonaws.com/email-api-micro1:3ceea66"
    essential = true
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
    }]
    environment = [{
      name  = "AWS_REGION"
      value = "us-east-2"
    }]
  }])
}

resource "aws_ecs_task_definition" "sqs_to_s3_task" {
  family                   = "sqs-to-s3-task"
  cpu                      = "128"
  memory                   = "256"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "sqs-to-s3-container"
    image     = "640107381183.dkr.ecr.us-east-2.amazonaws.com/sqs-to-s3-micro2:ed011af"
    essential = true
    environment = [
      {
        name  = "REGION"
        value = "us-east-2"
      },
      {
        name  = "BUCKET_NAME"
        value = aws_s3_bucket.email_storage_bucket.bucket
      },
      {
        name  = "QUEUE_URL"
        value = aws_sqs_queue.email_queue.id
      }
    ]
  }])
}

# === Load Balancer + Listener ===
resource "aws_lb" "email_api_alb" {
  name               = "email-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_service_sg.id]
  subnets = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id
  ]
  tags = {
    Name = "email-api-alb"
  }
}

resource "aws_lb_target_group" "email_api_tg" {
  name        = "email-api-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main_vpc.id
  target_type = "instance"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-499"
  }

  tags = {
    Name = "email-api-tg"
  }
}

resource "aws_lb_listener" "email_api_listener" {
  load_balancer_arn = aws_lb.email_api_alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.email_api_tg.arn
  }
}

# === ECS Service ===
resource "aws_ecs_service" "email_api_service" {
  name            = "email-api-service"
  cluster         = aws_ecs_cluster.devops_cluster.id
  task_definition = aws_ecs_task_definition.email_api_task.arn
  desired_count   = 1

  # Using capacity provider instead of launch_type
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_capacity_provider.name
    weight            = 1
  }
    
  load_balancer {
    target_group_arn = aws_lb_target_group.email_api_tg.arn
    container_name   = "email-api-container"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.email_api_listener]

  tags = {
    Name = "email-api-service"
  }
}

resource "aws_ecs_service" "sqs_to_s3_service" {
  name            = "sqs-to-s3-service"
  cluster         = aws_ecs_cluster.devops_cluster.id
  task_definition = aws_ecs_task_definition.sqs_to_s3_task.arn
  desired_count   = 1

  # Using capacity provider instead of launch_type
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_capacity_provider.name
    weight            = 1
  }
  
  depends_on = [aws_ecs_task_definition.sqs_to_s3_task]

  tags = {
    Name = "sqs-to-s3-service"
  }
}