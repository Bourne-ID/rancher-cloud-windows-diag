output "ip-address" {
  value = azurerm_public_ip.frontendloadbalancer_publicip.ip_address 
}

output "fqdn" {
  value =  azurerm_public_ip.frontendloadbalancer_publicip.fqdn
}

output "all_settings" {
  //Needed to prevent the destruction of the LB before the rancher join is destroyed
  value = null_resource.all_settings.id
}