output "lb_public_ip" {
  description = "LoadBalancer Public IP allocated for the resource."
  value       = azurerm_public_ip.pip.ip_address
}

output "mysql_fqdn" {
  value = azurerm_mysql_server.web-mysql-server.fqdn
}

output "current_subscription_display_name" {
  value = data.azurerm_subscription.current.display_name
}

output "current_subscription_tenant_id" {
  value = data.azurerm_subscription.current.tenant_id
}

output "current_subscription_placement_id" {
  value = data.azurerm_subscription.current.location_placement_id
}



output "random_password_password" {
  value = random_password.password.result 
}