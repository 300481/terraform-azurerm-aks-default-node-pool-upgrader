# external data provider to get the AzureRM Client Secret, which isn't available as any terraform variable
data "external" "client_secret" {
  program = ["/bin/sh", "-c", "${abspath(path.module)}/scripts/clientsecret.sh"]
}

# the null resource which runs the local-exec provisioner triggered by a change of the kubernetes_node_version
resource "null_resource" "node_pool_version" {
  triggers = {
    kubernetes_node_version = var.kubernetes_node_version
  }

  provisioner "local-exec" {
    command = "${abspath(path.module)}/scripts/update_node_version.sh"
    environment = {
      KUBERNETES_NODE_VERSION       = var.kubernetes_node_version
      ARM_CLIENT_SECRET_URL_ENCODED = urlencode(data.external.client_secret.result.clientsecret)
      RESOURCE_GROUP_NAME           = var.resource_group_name
      CLUSTER_NAME                  = var.kubernetes_cluster_name
      DEFAULT_POOL_NAME             = var.default_pool_name
    }
    interpreter = ["/bin/sh", "-c"]
  }
}
