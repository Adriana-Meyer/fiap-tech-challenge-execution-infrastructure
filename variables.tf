variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "eks_cluster_name" {
  description = "Fixed name of the EKS cluster provisioned by os-infrastructure. The cluster is found by this name, so no endpoint or credential is copied between repositories."
  type        = string
  default     = "tech-challenge-eks"
}

variable "service_name" {
  description = "Name of the service. It is also the namespace and the prefix of the command queue. The service's own manifests (k8s/) and its default configuration (COMMANDS_QUEUE) use these same names, so change it only together with them."
  type        = string
  default     = "execution"
}

variable "resource_quota" {
  description = "Ceiling for everything in the namespace. The service runs 1 to 2 replicas (HPA) of 250m/256Mi requests and 500m/512Mi limits; a rolling update briefly adds one more pod, so the values leave room for 3 pods (and a few extra for debugging). Every pod in the namespace must declare requests and limits, or the quota rejects it."
  type        = map(string)
  default = {
    "requests.cpu"           = "1"
    "requests.memory"        = "1Gi"
    "limits.cpu"             = "2"
    "limits.memory"          = "2Gi"
    "pods"                   = "6"
    "services.loadbalancers" = "1"
  }
}

variable "max_receive_count" {
  description = "How many times SQS delivers a command before moving it to the dead-letter queue."
  type        = number
  default     = 3
}

variable "queue_visibility_timeout_seconds" {
  description = "How long a command being handled stays hidden from other consumers. Must be longer than the slowest handling of one command."
  type        = number
  default     = 30
}
