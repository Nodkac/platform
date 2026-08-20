module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  # You need to reach the API server from your laptop.
  cluster_endpoint_public_access = true
  # Gives the IAM user running terraform admin rights on the cluster.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      capacity_type  = "SPOT"   
                                 # Trade-off: AWS can reclaim a node with 2 min notice.
      min_size     = 2
      max_size     = 3
      desired_size = 2

      # Public subnets require nodes to have public IPs to reach the internet.
      subnet_ids = module.vpc.public_subnets
    }
  }
}

# Creates an IAM role that a specific Kubernetes ServiceAccount is allowed to assume,
# trusted via the cluster's OIDC provider. This is IRSA.
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      # ONLY this namespace + serviceaccount can assume the role.
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

output "lb_controller_role_arn" {
  value = module.lb_controller_irsa.iam_role_arn
}