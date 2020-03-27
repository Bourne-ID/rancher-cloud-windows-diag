# Configure the Azure Provider
provider "azurerm" {
  subscription_id = var.azure_subscription_id
  features {}
}

data azurerm_subscription "current" {}

## Resource Groups 
# Rancher Resource Group
module "rancher-resource-group" {
  source = "./resourcegroup-module"

  group-name = var.rancher-resource-group-name
  region = var.rancher-region
}

# Kubernete Cluster Resource Group
module "k8s-resource-group" {
  source = "./resourcegroup-module"
  
  group-name = var.k8s-resource-group-name
  region = var.k8s-region
}


## Service Principals
resource "random_password" "rancher-serviceprincipal-password" {
  length = 32
  special = true
  override_special = "!"
}

module "rancher-serviceprincipal-module" {
  source = "./serviceprincipal-module"

  resource-group-id = module.rancher-resource-group.resource-group.id
  application-name = random_pet.mypet.id
  password = random_password.rancher-serviceprincipal-password.result
}

resource "random_password" "k8s-serviceprincipal-password" {
  length = 32
  special = true
  override_special = "!"
}

module "k8s-serviceprincipal-module" {
  source = "./serviceprincipal-module"

  resource-group-id = module.k8s-resource-group.resource-group.id
  application-name = "k8s-ccm-principal"
  password = random_password.k8s-serviceprincipal-password.result
}

# Storage Accounts for KeyVault
//module "rancher-storage-account" {
//  source = "./azure-storage-account-module"
//
//  resource-group = module.rancher-resource-group.resource-group
//  storage-account-name = "rancherkeyvault"
//}
//
//module "k8s-storage-account" {
//  source = "./azure-storage-account-module"
//
//  resource-group = module.k8s-resource-group.resource-group
//  storage-account-name = "k8skeyvault"
//}
//
//# KeyVaults to encrypt etcd
//module "rancher-keyvault" {
//  source = "./azure-keyvault-module"
//
//  tenant-id = data.azurerm_subscription.current.tenant_id
//  resource-group = module.rancher-resource-group.resource-group
//  vault-name = "rancherkeyvault"
//  serviceprincipal-id = module.rancher-serviceprincipal-module.service-principal-object-id
//}
//
//module "k8s-keyvault" {
//  source = "./azure-keyvault-module"
//
//  tenant-id = data.azurerm_subscription.current.tenant_id
//  resource-group = module.k8s-resource-group.resource-group
//  vault-name = "k8skeyvault"
//  serviceprincipal-id = module.k8s-serviceprincipal-module.service-principal-object-id
//}

# Nodes
locals {
   node-definition = {
    admin-username = var.node-credentials.admin-username
    ssh-keypath = var.node-credentials.ssh-keypath
    ssh-keypath-private = var.node-credentials.ssh-keypath-private
    size = "Standard_D2s_v3"
    disk-type = "Premium_LRS"
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
    docker-version = "18.09"
  }
}

## Networks
module "rancher-network" {
  source = "./network-module"

  resource-group = module.rancher-resource-group.resource-group

}

module "k8s-network" {
  source = "./network-module"

  resource-group = module.k8s-resource-group.resource-group
}


module "rancher-etcd" {
  source = "./node-module"
  prefix = "etcd"

  resource-group = module.rancher-resource-group.resource-group
  node-count = var.rancher-etcd-node-count
  subnet-id = module.rancher-network.subnet-id
  address-starting-index = 0
  node-definition = local.node-definition
}

module "rancher-control" {
  source = "./node-module"
  prefix = "control"

  resource-group = module.rancher-resource-group.resource-group
  node-count = var.rancher-controlplane-node-count
  subnet-id = module.rancher-network.subnet-id
  address-starting-index = var.rancher-etcd-node-count
  node-definition = local.node-definition  
}

module "rancher-worker" {
  source = "./node-module"
  prefix = "worker"

  resource-group = module.rancher-resource-group.resource-group
  node-count = var.rancher-worker-node-count
  subnet-id = module.rancher-network.subnet-id
  address-starting-index = var.rancher-etcd-node-count + var.rancher-controlplane-node-count
  node-definition = local.node-definition
}

module "front-end-lb" {
  source = "./loadbalancer-module"

  prefix = "worker"
  resource-group = module.rancher-resource-group.resource-group
  domain-name-label = var.rancher-domain-name
  backend-nics = module.rancher-worker.privateIps
}

resource rke_cluster "rancher-cluster" {
  depends_on = [module.rancher-etcd,module.rancher-control,module.rancher-worker]
  dynamic nodes {
    for_each = module.rancher-etcd.nodes
    content {
      address = module.rancher-etcd.publicIps[nodes.key].ip_address
      internal_address = module.rancher-etcd.privateIps[nodes.key].private_ip_address
      user    = module.rancher-etcd.node-definition.admin-username
      role    = [module.rancher-etcd.prefix]
      ssh_key = file(module.rancher-etcd.node-definition.ssh-keypath-private)
    }
  }

  dynamic nodes {
    for_each = module.rancher-control.nodes
    content {
      address = module.rancher-control.publicIps[nodes.key].ip_address
      internal_address = module.rancher-control.privateIps[nodes.key].private_ip_address
      user    = module.rancher-control.node-definition.admin-username
      role    = ["controlplane"]
      ssh_key = file(module.rancher-control.node-definition.ssh-keypath-private)
    }
  }

  dynamic nodes {
    for_each = module.rancher-worker.nodes
    content {
      address = module.rancher-worker.publicIps[nodes.key].ip_address
      internal_address = module.rancher-worker.privateIps[nodes.key].private_ip_address
      user    = module.rancher-worker.node-definition.admin-username
      role    = [module.rancher-worker.prefix]
      ssh_key = file(module.rancher-worker.node-definition.ssh-keypath-private)
    }
  }

  addons = <<EOL
---
kind: ServiceAccount
apiVersion: v1
metadata:
  name: tiller
  namespace: kube-system
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: tiller
  namespace: kube-system
subjects:
- kind: ServiceAccount
  name: tiller
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOL
}

resource "local_file" "kube-cluster-yaml" {
  filename = "${path.root}/kube_config_cluster.yml"
  content = rke_cluster.rancher-cluster.kube_config_yaml
}

resource "random_pet" "mypet" {}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

locals {
  domain-name = "${random_pet.mypet.id}.${var.rancher-domain-name}"
  my-ip-address = chomp(data.http.myip.body)
}

resource "null_resource" "initialize-helm" {
  depends_on = [local_file.kube-cluster-yaml]
  provisioner "local-exec" {
    command = file("../initialize-helm.sh")
  }
}

resource "null_resource" "install-cert-manager" {
  depends_on = [null_resource.initialize-helm]
  provisioner "local-exec" {
    command = file("../install-cert-manager.sh")
  }
}

resource "null_resource" "install-rancher" {
  depends_on = [null_resource.install-cert-manager]
  provisioner "local-exec" {
    command = templatefile("../install-rancher.sh", { lets-encrypt-email = var.lets-encrypt-email, lets-encrypt-environment = var.lets-encrypt-environment, rancher-domain-name = local.domain-name })
  }
}

resource "null_resource" "wait-for-rancher-ingress" {
  depends_on = [null_resource.install-rancher]
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "random_string" "random" {
  depends_on = [null_resource.wait-for-rancher-ingress]
  length = 32
  special = true
}

module "rancherbootstrap-module" {
  
  source = "./rancherbootstrap-module"

  rancher-url = "https://${local.domain-name}/"
  admin-password = random_string.random.result

  #todo: Dependencies as this fails on destroy
}


module "cluster-module" {
  source = "./cluster-module"

  cluster-name = "windowshybrid"
  rancher_api_url = module.rancherbootstrap-module.rancher-url
  rancher_api_token = module.rancherbootstrap-module.admin-token
  subscription-id = data.azurerm_subscription.current.subscription_id
  tenant-id = data.azurerm_subscription.current.tenant_id
  resource-group = module.k8s-resource-group.resource-group
  application-id = module.k8s-serviceprincipal-module.application-id
  secret = module.k8s-serviceprincipal-module.secret
  cloud = var.cloud
  vm-type = "vmss"
}

module "k8s-etcd" {
  source = "./nodevmss-module"
  prefix = "etcd"

  resource-group = module.k8s-resource-group.resource-group
  node-count = var.k8s-etcd-node-count
  subnet-id = module.k8s-network.subnet-id
  address-starting-index = 0
  node-definition = local.node-definition
  commandToExecute = "${module.cluster-module.linux-node-command} --etcd"
}

module "k8s-control" {
  source = "./nodevmss-module"
  prefix = "control"

  resource-group = module.k8s-resource-group.resource-group
  node-count = var.k8s-controlplane-node-count
  subnet-id = module.k8s-network.subnet-id
  address-starting-index = var.k8s-etcd-node-count
  node-definition = local.node-definition
  commandToExecute = "${module.cluster-module.linux-node-command} --controlplane"
}

module "k8s-worker" {
  source = "./nodevmss-module"
  prefix = "worker"

  resource-group = module.k8s-resource-group.resource-group
  node-count = var.k8s-worker-node-count
  subnet-id = module.k8s-network.subnet-id
  address-starting-index = var.k8s-etcd-node-count + var.k8s-controlplane-node-count
  node-definition = local.node-definition
  commandToExecute = "${module.cluster-module.linux-node-command} --worker"
}

resource "random_string" "windows-admin-password" {
  length = 32
  special = true
}

locals {
  windows-node-definition = {
    admin-username = local.node-definition.admin-username
    admin-password = random_string.windows-admin-password.result
    size = "Standard_D4s_v3"
    disk-type = "Premium_LRS"
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "Datacenter-Core-1903-with-Containers-smalldisk"
    version   = "latest"
  }
}

module "k8s-windows" {
  source = "./windowsnodevmss-module"
  prefix = "win"

  resource-group = module.k8s-resource-group.resource-group
  node-count = var.k8s-windows-node-count
  subnet-id = module.k8s-network.subnet-id
  address-starting-index = var.k8s-etcd-node-count + var.k8s-controlplane-node-count + var.k8s-worker-node-count
  node-definition = local.windows-node-definition
  join-command = module.cluster-module.windows-node-commmand
}

// Needed for VM Standard
//module "join-rancher" {
//  source = "./join-rancher-module"
//
//  resource-group = module.k8s-resource-group.resource-group
//  node-count = var.k8s-windows-node-count
//  nodes = module.k8s-windows.nodes
//  public-Ips = module.k8s-windows.publicIps
//  private-Ips = module.k8s-windows.privateIps
//  join-command = module.cluster-module.windows-node-commmand
//}

module "route53" {
  source = "./route53-module"
  access_key = var.aws_access_key
  access_secret = var.aws_access_secret
  domain_name = local.domain-name
  zone_id = var.zone_id
  fqdn = module.front-end-lb.fqdn
}