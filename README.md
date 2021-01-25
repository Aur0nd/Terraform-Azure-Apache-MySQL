# Terraform-Azure-Apache-MySQL
Deploy HA Apache servers &amp; Azure Managed MySQL



# Generate ssh key
ssh-keygen -t rsa -b 4096 -f mykey
```
# Run Terraform
terraform init
terraform apply
```

# Ssh into virtual machine
The output of terraform shows the public ip

```
ssh avalanche@PUBLIC_IP_HERE -i mykey -p 50001
```

# Install MySQL client & Connect to MySQL from virtual machine
The output of terraform shows the dns of the MySQL

```
sudo apt-get update
sudo apt-get install mysql-client-5.7
mysql -h DNSNAMEHERE -u mysqladmin@mysql-training -p
```
