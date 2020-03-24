
# Configure the Rancher2 provider
provider "rancher2" {
  api_url    = var.rancher_api_url
  token_key  = var.rancher_api_token

  insecure = true
}


################################## Rancher
resource "rancher2_cluster" "manager" {
  name = var.cluster-name
  description = "Hybrid cluster with Windows and Linux workloads"
  # windows_prefered_cluster = true Not currently supported
  rke_config {
    kubernetes_version = "v1.15.9-rancher1-1"
    network {
      plugin = "flannel"
      options = {
        flannel_backend_port = 4789
        flannel_backend_type = "vxlan"
        flannel_backend_vni = 4096
      }
    }
     cloud_provider {
       azure_cloud_provider {
         aad_client_id =  var.application-id
         aad_client_secret = var.secret
         subscription_id = var.subscription-id
         tenant_id = var.tenant-id
       }
     }
  }
}
