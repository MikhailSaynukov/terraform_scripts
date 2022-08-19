terraform {
  required_providers {
    sbercloud = {
      source  = "sbercloud.terraform.com/local/sbercloud" # Initialize SberCloud provider
    }
  }
}

# Configure SberCloud provider
provider "sbercloud" {
  auth_url = var.auth_url # Authorization address
  region   = var.region # The region where the cloud infrastructure will be deployed

  # Authorization keys
  access_key = var.ak
  secret_key = var.sk
}

data "sbercloud_availability_zones" "myaz" {}

data "sbercloud_vpc" "bastion_vpc" {
  name = var.bastion_vpc_name
}

data "sbercloud_vpc_subnet" "bastion_subnet" {
  name = var.bastion_subnet_name
}

data "sbercloud_rds_flavors" "flavors" {
  db_type       = "MySQL"
  db_version    = "8.0"
  instance_mode = "single"
}

# Create VPS, Subnet

resource "sbercloud_vpc" "vpc" {
  name = var.vpc_name
  cidr = var.vpc_cidr
  tags = {
    created-by = "terraform"
    app = "rds-mysql"
  }
}

resource "sbercloud_vpc_subnet" "subnet" {
  name       = var.subnet_name
  cidr       = var.subnet_cidr
  gateway_ip = var.subnet_gateway_ip
  vpc_id     = sbercloud_vpc.vpc.id
  primary_dns = var.primary_dns
  secondary_dns = var.secondary_dns

  tags = {
    created-by = "terraform"
    app = "rds-mysql"
  }
}

# Create interconnection with bastion and VPC network

resource "sbercloud_vpc_peering_connection" "peering" {
  name        = var.peer_conn_name
  vpc_id      = sbercloud_vpc.vpc.id
  peer_vpc_id = data.sbercloud_vpc.bastion_vpc.id
}

resource "sbercloud_vpc_route" "vpc_route_1" {
  type        = "peering"
  nexthop     = sbercloud_vpc_peering_connection.peering.id
  destination = sbercloud_vpc_subnet.subnet.cidr
  vpc_id      = data.sbercloud_vpc.bastion_vpc.id
}

resource "sbercloud_vpc_route" "vpc_route_2" {
  type        = "peering"
  nexthop     = sbercloud_vpc_peering_connection.peering.id
  destination = data.sbercloud_vpc_subnet.bastion_subnet.cidr
  vpc_id      = sbercloud_vpc.vpc.id
}

# Create Security Group and RDS instance

resource "sbercloud_networking_secgroup" "sg-ecs-A-hosts" {
  name        = "sg-rds-mysql"
  description = "Security group for RDS mysql"
}

resource "sbercloud_networking_secgroup_rule" "ecs-A-tcp-3306" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3306
  port_range_max    = 3306
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = sbercloud_networking_secgroup.sg-ecs-A-hosts.id
}

resource "sbercloud_rds_instance" "rds_instance" {
  name              = "MySQL_rds_instance"
  flavor            = data.sbercloud_rds_flavors.flavors.flavors[index(data.sbercloud_rds_flavors.flavors.flavors[*].vcpus, var.vpcus_required)].name
  vpc_id            = sbercloud_vpc.vpc.id
  subnet_id         = sbercloud_vpc_subnet.subnet.id
  security_group_id = sbercloud_networking_secgroup.sg-ecs-A-hosts.id
  availability_zone = [data.sbercloud_availability_zones.myaz.names[0]]
  
  db {
    type     = "MySQL"
    version  = "8.0"
    password = var.admin_pass
    port = 3306
  }

  volume {
    type = "HIGH"
    size = 40
  }

  backup_strategy {
    start_time = "01:00-02:00"
    keep_days  = 1
  }
}
