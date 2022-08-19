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

data "sbercloud_compute_flavors" "myflavor" {
  availability_zone = data.sbercloud_availability_zones.myaz.names[0]
  performance_type  = "normal"
  cpu_core_count    = 1
  memory_size       = 2
}

data "sbercloud_images_image" "myimage" {
  name        = "Ubuntu 20.04 server 64bit"
  most_recent = true
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
    app = "LB-nginx"
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
    app = "LB-nginx"
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

# Create two hosts, update repo and install nginx

resource "sbercloud_compute_instance" "A2" {
  name              = "ecs-A2-terraform"
  image_id          = data.sbercloud_images_image.myimage.id
  flavor_id         = data.sbercloud_compute_flavors.myflavor.ids[0]
  security_groups   = [sbercloud_networking_secgroup.sg-ecs-A-hosts.name]
  availability_zone = data.sbercloud_availability_zones.myaz.names[0]
  system_disk_type = "SAS"
  system_disk_size = 10
  tags = {
    name = "ecs-A2"
    created-by = "terraform"
    env = "test"
    apps = "LB-nginx"
  }
  admin_pass = var.admin_pass
  network {
    uuid = sbercloud_vpc_subnet.subnet.id
  }
  connection {
    type     = "ssh"
    user     = "root"
    agent    = "false"
    password = var.admin_pass
    host     = sbercloud_compute_instance.A2.access_ip_v4
  }
  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get -y install nginx",
    ]
  }
}

resource "sbercloud_compute_instance" "A3" {
  name              = "ecs-A3-terraform"
  image_id          = data.sbercloud_images_image.myimage.id
  flavor_id         = data.sbercloud_compute_flavors.myflavor.ids[0]
  security_groups   = [sbercloud_networking_secgroup.sg-ecs-A-hosts.name]
  availability_zone = data.sbercloud_availability_zones.myaz.names[0]
  system_disk_type = "SAS"
  system_disk_size = 10
  tags = {
    name = "ecs-A3"
    created-by = "terraform"
    env = "test"
    apps = "LB-nginx"
  }
  admin_pass = var.admin_pass
  network {
    uuid = sbercloud_vpc_subnet.subnet.id
  }
  connection {
    type     = "ssh"
    user     = "root"
    agent    = "false"
    password = var.admin_pass
    host     = sbercloud_compute_instance.A3.access_ip_v4
  }
  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get -y install nginx",
    ]
  }  
}

# Create 2 EIPs for NAT GW and ELB

resource "sbercloud_vpc_eip" "eip_1" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    share_type  = "PER"
    name        = "bw-ecs-hosts-terraform"
    size        = 1
    charge_mode = "traffic"
  }
}

resource "sbercloud_vpc_eip" "eip_2" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    share_type  = "PER"
    name        = "bw-ecs-elb-nginx-terraform"
    size        = 1
    charge_mode = "traffic"
  }
}
# Create NAT GW

resource "sbercloud_nat_gateway" "nat_ecs_A" {
  name                = "nat_ecs_A"
  description         = "Nat for ecs A hosts"
  spec                = "1"
  subnet_id           = sbercloud_vpc_subnet.subnet.id
  vpc_id              = sbercloud_vpc.vpc.id
}

resource "sbercloud_nat_snat_rule" "snat_ecs_A_to_internet" {
  nat_gateway_id = sbercloud_nat_gateway.nat_ecs_A.id
  subnet_id           = sbercloud_vpc_subnet.subnet.id
  floating_ip_id = sbercloud_vpc_eip.eip_1.id
 
}

# Create Security Group with Inbound rules for 22 and 80 port 

resource "sbercloud_networking_secgroup" "sg-ecs-A-hosts" {
  name        = "sg-ecs-A-hosts"
  description = "Security group for hosts"
}

resource "sbercloud_networking_secgroup_rule" "ecs-A-ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = sbercloud_networking_secgroup.sg-ecs-A-hosts.id
}

resource "sbercloud_networking_secgroup_rule" "ecs-A-tcp-80" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = sbercloud_networking_secgroup.sg-ecs-A-hosts.id
}

# Create ELB for Nginx, Listener on port 80 and Backend pool

resource "sbercloud_lb_loadbalancer" "elb-ecs-A-nginx" {
  vip_subnet_id = sbercloud_vpc_subnet.subnet.subnet_id
  name = "elb-ecs-A-nginx"
}

resource "sbercloud_networking_eip_associate" "eip_1" {
  public_ip = sbercloud_vpc_eip.eip_2.address
  port_id   = sbercloud_lb_loadbalancer.elb-ecs-A-nginx.vip_port_id
}

resource "sbercloud_lb_listener" "listener_1" {
  protocol        = "TCP"
  protocol_port   = 80
  loadbalancer_id = sbercloud_lb_loadbalancer.elb-ecs-A-nginx.id
  name = "tcp-80-listener"
}

resource "sbercloud_lb_pool" "pool_1" {
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = sbercloud_lb_listener.listener_1.id
  name = "nginx-cluster-tcp-80"
}

# Add members to Backend pool

resource "sbercloud_lb_member" "member_1" {
  address       = sbercloud_compute_instance.A2.access_ip_v4
  protocol_port = 80
  pool_id       = sbercloud_lb_pool.pool_1.id
  subnet_id     = sbercloud_vpc_subnet.subnet.subnet_id
}

resource "sbercloud_lb_member" "member_2" {
  address       = sbercloud_compute_instance.A3.access_ip_v4
  protocol_port = 80
  pool_id       = sbercloud_lb_pool.pool_1.id
  subnet_id     = sbercloud_vpc_subnet.subnet.subnet_id
}