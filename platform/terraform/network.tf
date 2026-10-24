data "aws_availability_zones" "available" {
  state = "available"
}

# VPC sur 2 zones de disponibilité : sous-réseaux publics (NLB, usine DevOps) et privés (nœuds EKS)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16"

  name = var.project
  cidr = "10.20.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnets = ["10.20.10.0/24", "10.20.11.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # 1 seule NAT : suffisant pour un projet étudiant, divise le coût
  enable_dns_hostnames = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
