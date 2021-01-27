provider "azurerm" {
    version = "=1.35.0"
    
}

provider "random" {
  version = "2.2"
}

resource "azurerm_resource_group" "web-resource-group" {
    name                    = "${var.resource_prefix["key1"]}-resource-group"
    location                = var.location
}   

#Networking
resource "azurerm_virtual_network" "web-virtual-network" {
    name                = "${var.resource_prefix["key2"]}-virtual-network"
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name 
    address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "web-subnet" {
    name                 = "${var.resource_prefix["key2"]}-subnet"
    resource_group_name  = azurerm_resource_group.web-resource-group.name
    virtual_network_name = azurerm_virtual_network.web-virtual-network.name
    address_prefix     = "10.0.0.0/24"
    service_endpoints    = ["Microsoft.Sql"] # Extend subnet to allow SQL
}

resource "azurerm_subnet" "web-subnet-db" {
    name                 = "${var.resource_prefix["key2"]}-subnet-db"
    resource_group_name  = azurerm_resource_group.web-resource-group.name
    virtual_network_name = azurerm_virtual_network.web-virtual-network.name
    address_prefix     = "10.0.1.0/24"
    service_endpoints    = ["Microsoft.Sql"] # Extend subnet to allow SQL
}

resource "azurerm_network_security_group" "web-network-security-group" {
    name                = "${var.resource_prefix["key2"]}-security-group"
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name
    security_rule {
        name                       = "HTTP"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"       
    }   

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"        
    }  
}

resource "azurerm_public_ip" "pip" {
    name                = "public-ip"
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name
    sku                 = length(var.zones) == 0 ? "Basic" : "Standard" #IP can route traffic between AZs if its Standard
    allocation_method   = "Static"
    domain_name_label   = azurerm_resource_group.web-resource-group.name
}


#Load Balancer


resource "azurerm_lb" "web-load-balancers" {
    name                = "web-lb"
    sku                 = length(var.zones) == 0 ? "Basic" : "Standard" # Standard will move LB and PIP to a health AZ automatically if sth happens
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name

    frontend_ip_configuration {
        name                    =  "PublicIPAddress"
        public_ip_address_id    =  azurerm_public_ip.pip.id 
    }       
}

resource "azurerm_lb_backend_address_pool" "web-backend-pool-lb" { #All VMs will join this backend pool
    name                    = "BackEndAddressPool"                  # This way, load balancer will route traffic to the VMs
    resource_group_name     = azurerm_resource_group.web-resource-group.name 
    loadbalancer_id         = azurerm_lb.web-load-balancers.id
}

resource "azurerm_lb_nat_pool" "web-nat-pool" {
    name                                = "ssh"
    resource_group_name                 = azurerm_resource_group.web-resource-group.name 
    loadbalancer_id                     = azurerm_lb.web-load-balancers.id 
    protocol                            = "Tcp"
    frontend_port_start                 = 50000
    frontend_port_end                   = 50119 
    backend_port                        = 22
    frontend_ip_configuration_name      = "PublicIPAddress"
}

resource "azurerm_lb_probe" "web-lb-probe" {  #HEALTH CHECK
    name                                = "httpd-probe"
    resource_group_name                 = azurerm_resource_group.web-resource-group.name 
    loadbalancer_id                     = azurerm_lb.web-load-balancers.id 
    protocol                            = "http"
    request_path                        = "/"
    port                                = 80
}

resource "azurerm_lb_rule" "web-lb-rule" {
    name                                = "lb-rule"
    resource_group_name                 = azurerm_resource_group.web-resource-group.name 
    loadbalancer_id                     = azurerm_lb.web-load-balancers.id 
    protocol                            = "Tcp"
    frontend_port                       = 80
    backend_port                        = 80
    frontend_ip_configuration_name      = "PublicIPAddress"
    probe_id                            =  azurerm_lb_probe.web-lb-probe.id 
    backend_address_pool_id             =  azurerm_lb_backend_address_pool.web-backend-pool-lb.id 
}





                               # Virtual Machine / Scale Sets

resource "azurerm_virtual_machine_scale_set" "web-scale-set" {
    name                = "${var.resource_prefix["key1"]}-scale-set"
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name    

         #Auto Rolling upgrade
    automatic_os_upgrade = true 
    upgrade_policy_mode  = "Rolling"

    rolling_upgrade_policy {
        max_batch_instance_percent              = 20
        max_unhealthy_instance_percent           = 20
        max_unhealthy_upgraded_instance_percent = 5
        pause_time_between_batches              = "PT0S" #Pause Time 0 Seconds
    }
         #must, for rolling upgrade policy
    health_probe_id = azurerm_lb_probe.web-lb-probe.id # Load Balancer is making the Health Checks
    zones           = var.zones 
    sku {
        name       = "Standard_A1_v2"
        tier       = "Standard"
        capacity   = 2
    }
  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  storage_profile_data_disk { #THIS WILL NOT BE ERASED IF WE DO OS UPGRADE
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }
  os_profile {
    computer_name_prefix = "avalanche"
    admin_username       = "avalanche"
    custom_data          = "#!/bin/bash\napt-get update && apt-get install -y apache2 && systemctl enable httpd.service && systemctl start httpd.service && apt-get install mysql-client-5.7 -y "
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file("mykey.pub")
      path     = "/home/avalanche/.ssh/authorized_keys"
    }
  }

  network_profile {
      name          = "networkprofile"
      primary       = true 
      network_security_group_id = azurerm_network_security_group.web-network-security-group.id 
      ip_configuration {
          name                                      = "IPConfiguration"
          primary                                   = true 
          subnet_id                                 = azurerm_subnet.web-subnet.id
          load_balancer_backend_address_pool_ids    = [azurerm_lb_backend_address_pool.web-backend-pool-lb.id]
          load_balancer_inbound_nat_rules_ids       = [azurerm_lb_nat_pool.web-nat-pool.id]
      }
  }
}

resource "azurerm_monitor_autoscale_setting" "web-monitor-autoscale-setting" {
  name                = "web-autoscaling"
  resource_group_name = azurerm_resource_group.web-resource-group.name
  location            = var.location    
  target_resource_id  = azurerm_virtual_machine_scale_set.web-scale-set.id

  profile {
      name = "defaultProfile"
      capacity {
          default = 2
          minimum = 2
          maximum = 4
      }
      rule {
          metric_trigger {
              metric_name       = "Percentage CPU"
              metric_resource_id = azurerm_virtual_machine_scale_set.web-scale-set.id
              time_grain        = "PT1M" # TAKES STATISTICS EVERY 1m  (CHECK ON AZURE PORTAL)
              statistic         = "Average"
              time_window       = "PT5M"  # IT WILL WAIT 5m BEFORE DEPLOYING
              time_aggregation  = "Average"
              operator          = "GreaterThan"
              threshold         = 40 #if Greater than 40% utilization then scale up
          }
          scale_action {
              direction = "Increase"
              type      = "ChangeCount"
              value     = "1"
              cooldown  = "PT1M"  # NO MORE CHECKS WILL BE DONE FOR 1m
          }
      }

      rule {
        metric_trigger {
              metric_name       = "Percentage CPU"
              metric_resource_id = azurerm_virtual_machine_scale_set.web-scale-set.id
              time_grain        = "PT1M"
              statistic         = "Average"
              time_window       = "PT5M"
              time_aggregation  = "Average"
              operator          = "lessThan"
              threshold         = 10
        }
        scale_action {
            direction = "Decrease"
            type      = "ChangeCount"
            value     = "1"
            cooldown  = "PT1M"
        }
      }
  }
  notification {
    email {
      send_to_subscription_administrator    = true
      send_to_subscription_co_administrator = true
      custom_emails                         = ["george.ziongkas@blackswan.com"]
    }
  }
}



   # DATABASE MYSQL

resource "random_string" "random" {
  length  = 8
  upper   = false
  special = false
  number  = false
}

resource "azurerm_mysql_server" "web-mysql-server" {
    name                = "database${random_string.random.result}" #Must be unique 
    location            = var.location
    resource_group_name = azurerm_resource_group.web-resource-group.name 
    
    sku {
        name            = "GP_Gen5_2"
        capacity        = 2
        tier            = "GeneralPurpose"
        family          = "Gen5"
    }
    storage_profile {
        storage_mb      = 5120
        backup_retention_days = 7
        geo_redundant_backup  = length(var.envi) == 0 ? "Disabled" : "Enabled"    #Enable if in PROD                 
    }
    
    
  resource "random_password" "password" {
        length = 16
        special = true
        override_special = "_%@"
  }

    
    
    administrator_login             = "mysqladmin"
    administrator_login_password    = random_password.password.result
    version                         = "5.7"
    ssl_enforcement                 = "Enabled"
}

resource "azurerm_mysql_database" "web-mysql-db" {
    name                            = "snipeit"
    resource_group_name             =  azurerm_resource_group.web-resource-group.name 
    server_name                     = azurerm_mysql_server.web-mysql-server.name 
    charset                         = "utf8"
    collation                       = "utf8_unicode_ci"
}

# THIS WILL ALLOW THESE TWO SUBNETS TO CONNECT TO THE DB..
resource "azurerm_mysql_virtual_network_rule" "web-database-subnet-vnet-rule" {
    name                            = "mysql-vnet-rule"
    resource_group_name             = azurerm_resource_group.web-resource-group.name
    server_name                     = azurerm_mysql_server.web-mysql-server.name 
    subnet_id                       = azurerm_subnet.web-subnet.id
}

resource "azurerm_mysql_virtual_network_rule" "web-subnet-vnet-rule" {
    name                            = "mysql-subnet-vnet-rule"
    resource_group_name             = azurerm_resource_group.web-resource-group.name
    server_name                     = azurerm_mysql_server.web-mysql-server.name 
    subnet_id                       = azurerm_subnet.web-subnet-db.id
}

resource "azurerm_mysql_firewall_rule" "demo-allow-demo-instance" { 
  name                = "mysql-demo-instance"
  resource_group_name = azurerm_resource_group.web-resource-group.name
  server_name         = azurerm_mysql_server.web-mysql-server.name
  start_ip_address    = "10.0.0.0"
  end_ip_address      = "10.0.1.0"
}


