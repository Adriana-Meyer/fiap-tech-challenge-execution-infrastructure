# The service's own namespace. The service repository deploys into it and fails
# with a clear message if it is missing (deploy-aws.yml: "Check the namespace exists").
resource "kubernetes_namespace_v1" "service" {
  metadata {
    name = var.service_name

    labels = {
      "app.kubernetes.io/part-of" = "workshop"
      "workshop/service"          = var.service_name
    }
  }
}

# Keeps one service from starving the others on the shared cluster: the nodes
# are few and the Learner Lab budget is small. It also caps the load balancers
# at one, because every service gets its own NLB (a forgotten LoadBalancer
# Service would keep costing money after the Lab session ends).
resource "kubernetes_resource_quota_v1" "service" {
  metadata {
    name      = "${var.service_name}-quota"
    namespace = kubernetes_namespace_v1.service.metadata[0].name
  }

  spec {
    hard = var.resource_quota
  }
}
