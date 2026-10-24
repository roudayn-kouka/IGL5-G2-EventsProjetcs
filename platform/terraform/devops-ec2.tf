# =============================================================================
#  EC2 « usine DevOps » : Jenkins, Nexus, SonarQube (configurée ensuite par Ansible)
# =============================================================================
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "devops" {
  key_name   = "${var.project}-devops"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "devops" {
  name        = "${var.project}-devops"
  description = "Usine DevOps : HTTPS public (Caddy), SSH restreint"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH (Ansible)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "HTTP (challenge Let's Encrypt)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS (Jenkins, SonarQube, Nexus, webhooks GitHub)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "HTTPS vers GitHub, AWS et les registres"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "HTTP vers les miroirs de paquets"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [format("%s/32", cidrhost(module.vpc.vpc_cidr_block, 2))]
  }
  egress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [format("%s/32", cidrhost(module.vpc.vpc_cidr_block, 2))]
  }
}

# Rôle IAM de l'instance : Jenkins pousse dans ECR sans aucune clé AWS stockée
resource "aws_iam_role" "devops" {
  count = local.use_lab_role ? 0 : 1
  name  = "${var.project}-devops"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "devops_ecr" {
  count = local.use_lab_role ? 0 : 1
  name  = "ecr-push"
  role  = aws_iam_role.devops[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect = "Allow"
        Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Resource = aws_ecr_repository.events_app.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "devops" {
  count = local.use_lab_role ? 0 : 1
  name  = "${var.project}-devops"
  role  = aws_iam_role.devops[0].name
}

resource "aws_instance" "devops" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.devops_instance_type
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.devops.id]
  key_name               = aws_key_pair.devops.key_name
  iam_instance_profile   = local.use_lab_role ? "LabInstanceProfile" : aws_iam_instance_profile.devops[0].name

  root_block_device {
    volume_size = 60
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 obligatoire
    http_put_response_hop_limit = 2          # accessible depuis les conteneurs (Jenkins)
  }

  tags = { Name = "${var.project}-devops" }
}

resource "aws_eip" "devops" {
  instance = aws_instance.devops.id
  domain   = "vpc"
  tags     = { Name = "${var.project}-devops" }
}
