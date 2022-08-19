ak = ""
sk = ""
auth_url = ""
region = "ru-moscow-1"
admin_pass = ""
vpc_name = "vpc-A"
vpc_cidr = "192.168.0.0/24"
subnet_name = "subnet-A"
subnet_cidr = "192.168.0.0/28"
subnet_gateway_ip = "192.168.0.1"
peer_conn_name = "Peer-with-bastion"
bastion_vpc_name = "vpc-B" # VPC where bastion host will be located. It will ssh to newly created hosts and install nginx
bastion_subnet_name = "subnet-B"
primary_dns = "100.125.13.59" # Will not be set if not specified
secondary_dns = "100.125.65.14" # Will not be set if not specified

