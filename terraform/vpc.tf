# A community module — thousands of people use and maintain this.
# Writing raw VPC resources by hand is a week of work and teaches nothing extra.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "platform"
  cidr = "10.0.0.0/16"

  # Two AZs: EKS requires a minimum of two for the control plane.
  azs = ["${var.region}a", "${var.region}b"]

  # Public subnets now hold ONLY the load balancer.
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  # Private subnets hold the worker nodes. No route to an internet gateway,
  # so nothing on the internet can reach them directly.
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  # NAT gateway: lets private nodes make OUTBOUND connections (image pulls,
  # AWS API calls) while remaining unreachable from the internet.
  enable_nat_gateway = true
  # ONE NAT for the whole VPC instead of one per AZ.
  # ~$32/mo instead of ~$64/mo. Trade-off: if the NAT's AZ fails, egress fails
  # cluster-wide. Acceptable here because losing egress does not stop
  # already-running pods from serving traffic through the ALB — it only blocks
  # new image pulls and outbound API calls. See docs/adr/002-private-subnets.md
  single_nat_gateway = true

  enable_dns_hostnames = true

  # These tags are how the AWS Load Balancer Controller decides subnet placement.
  # Getting them wrong causes an ALB that never gets an address, with no clear error.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
