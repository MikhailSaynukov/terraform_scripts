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

#Read necessary resources config data

data "sbercloud_availability_zones" "myaz" {}

data "sbercloud_compute_flavors" "myflavor" {
  availability_zone = data.sbercloud_availability_zones.myaz.names[0]
  performance_type  = "normal"
  cpu_core_count    = 1
  memory_size       = 2
}

data "sbercloud_vpc_subnet" "mynet" {
  name = "subnet-A"
}

data "sbercloud_images_image" "myimage" {
  name        = "Ubuntu 20.04 server 64bit"
  most_recent = true
}

#Create Security Group for hosts

resource "sbercloud_networking_secgroup" "sg-ecs-A-hosts" {
  name        = "sg-ecs-A-hosts"
  description = "Security group for hosts A2 and A3"
}

#Create hosts A2 and A3

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
  }
  admin_pass = var.admin_pass
  network {
    uuid = data.sbercloud_vpc_subnet.mynet.id
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
  }
  admin_pass = var.admin_pass
  network {
    uuid = data.sbercloud_vpc_subnet.mynet.id
  }
}