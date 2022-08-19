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

data "sbercloud_enterprise_project" "enterprise_project" {
  name = "saynukov-test"
}

data "sbercloud_vpc" "bastion_vpc" {
  name = var.bastion_vpc_name
}

data "sbercloud_vpc_subnet" "bastion_subnet" {
  name = var.bastion_subnet_name
}

# Create VPS, Subnet

resource "sbercloud_vpc" "vpc" {
  name = var.vpc_name
  cidr = var.vpc_cidr
  tags = {
    created-by = "terraform"
    app = "cce-cluster"
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
    app = "cce-cluster"
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

# Create cluster with EIP

resource "sbercloud_vpc_eip" "cce_ext_eip" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "cce-external-ip"
    size        = 1
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "sbercloud_cce_cluster" "cluster" {
  name                   = "cce-cluster"
  multi_az               = true
  cluster_type           = "VirtualMachine"
  flavor_id              = "cce.s2.small"
  vpc_id                 = sbercloud_vpc.vpc.id
  subnet_id              = sbercloud_vpc_subnet.subnet.id
  container_network_type = "vpc-router" # Only supported for workers with Ubuntu OS only
  authentication_mode    = "rbac"
  eip                    = sbercloud_vpc_eip.cce_ext_eip.address
  enterprise_project_id  = data.sbercloud_enterprise_project.enterprise_project.id
  tags = {
    created_by = "terraform"
   }
} 

/*
resource "sbercloud_cce_node" "node" {
  cluster_id        = sbercloud_cce_cluster.cluster.id
  name              = "cce-worker1"
  flavor_id         = "s6.large.2"
  availability_zone = data.sbercloud_availability_zones.myaz.names[0]
  password = var.admin_pass
  os = "Ubuntu 18.04 server 64bit"

  root_volume {
    size       = 40
    volumetype = "SAS"
  }
  data_volumes {
    size       = 100
    volumetype = "SAS"
  }
}
*/

resource "sbercloud_cce_node_pool" "node_pool" {
  cluster_id               = sbercloud_cce_cluster.cluster.id
  name                     = "cce-worker-pool"
  os                       = "Ubuntu 18.04"
  initial_node_count       = 2
  flavor_id                = "s6.large.2"
  password = var.admin_pass
  scall_enable             = true
  min_node_count           = 1
  max_node_count           = 10
  scale_down_cooldown_time = 100
  priority                 = 1
  type                     = "vm"

  root_volume {
    size       = 40
    volumetype = "SAS"
  }
  data_volumes {
    size       = 100
    volumetype = "SAS"
  }

  tags = {
    created_by = "terraform"
  }
}

  resource "sbercloud_cce_addon" "metrics_server" {
  cluster_id    = sbercloud_cce_cluster.cluster.id
  template_name = "metrics-server"
  version       = "1.1.10"
}

output "ca_cert" {
  value       = sbercloud_cce_cluster.cluster.certificate_clusters[0].certificate_authority_data
}

output "user_cert" {
  value       = sbercloud_cce_cluster.cluster.certificate_users[0].client_certificate_data
}

output "user_key" {
  value       = sbercloud_cce_cluster.cluster.certificate_users[0].client_key_data
}

output "cluster_address" {
  value       = sbercloud_cce_cluster.cluster.certificate_clusters[0].server
}

output "cluster_name" {
  value       = sbercloud_cce_cluster.cluster.certificate_clusters[0].name
}

output "user_name" {
  value       = sbercloud_cce_cluster.cluster.certificate_users[0].name
}