# Finds the cluster created by os-infrastructure by its fixed name, the same way
# os-database-infrastructure finds its network: no manual copy-paste of
# endpoints between repositories and no coupling to another repo's state.
# os-infrastructure must have been applied, in the same AWS session, before this one.
data "aws_eks_cluster" "main" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}
