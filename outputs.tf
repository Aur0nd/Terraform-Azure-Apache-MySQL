output "lb_public_ip" {
  description = "LoadBalancer Public IP allocated for the resource."
  value       = azurerm_public_ip.pip.ip_address
}

output "mysql_fqdn" {
  value = azurerm_mysql_server.web-mysql-server.fqdn
}
