# A community module — thousands of people use and maintain this.
# Writing raw VPC resources by hand is a week of work and teaches nothing extra.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "platform"
  cidr = "10.0.0.0/16"

  # Two AZs: EKS requires a minimum of two for the control plane.
  azs            = ["${var.region}a", "${var.region}b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # No NAT gateway = saves ~$32/month. Nodes get public IPs instead,
  # which is why they can pull images. Phase 6 changes this deliberately.
  enable_nat_gateway      = false
  map_public_ip_on_launch = true

  enable_dns_hostnames = true

  # The AWS Load Balancer Controller reads this tag to decide where to
  # place internet-facing load balancers. Missing it = ALB never gets an address.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}


