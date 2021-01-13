variable "kubernetes_node_version" {
  type        = string
  default     = "empty"
  description = "The Kubernetes Version for the default node pool."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the Resource Group which contains the Kubernetes Cluster."
}

variable "kubernetes_cluster_name" {
  type        = string
  description = "The name of the Kubernetes Cluster."
}

variable "default_pool_name" {
  type        = string
  description = "The name of the default node pool."
}