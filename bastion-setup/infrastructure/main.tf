#########################################################
#        Generate SSH keys for the machines
#       
##########################################################

 
resource "tls_private_key" "controller-ssh-keys" {
  count = var.controller_count
  algorithm   = "RSA"
  rsa_bits  = "4096"
}
resource "tls_private_key" "work-ssh-keys" {
  count = var.worker_count
  algorithm   = "RSA"
  rsa_bits  = "4096"
}

resource "tls_private_key" "bastion-ssh-key" {
    
  algorithm   = "RSA"
  rsa_bits  = "4096"
}


resource "local_file" "write-worker-privatekeys" {
    count = var.worker_count
    content     =  tls_private_key.work-ssh-keys[count.index].private_key_pem 
    filename = "../ssh_keys/kube-worker-${count.index}"
    file_permission = "600"
}
resource "local_file" "write-controller-privatekeys" {
    count = var.controller_count
    content     =  tls_private_key.controller-ssh-keys[count.index].private_key_pem 
    filename = "../ssh_keys/kube-controller-${count.index}"
    file_permission = "600"
}

resource "local_file" "write-bastion-privatekeys" {
   
    content     =  tls_private_key.bastion-ssh-key.private_key_pem 
    filename = "../ssh_keys/bastion"
    file_permission = "600"
}


#####################---END---################

#########################################################
#        Provision Bastion server, 3 controllers and 3 workers
#       
##########################################################
provider "google" {
  credentials             = file("myproject-604c9625f6b6.json")
  region                  =  "us-west1"
   project                 = "myproject"
  
}

# # retrieve all the zones in region
data "google_compute_zones" "available" {
   region                  =  "us-west1"
}

resource "google_compute_network" "kube-network" {
  name                    = "kube-network"
  description             = "kubernetes vpc network"
  auto_create_subnetworks = false
   
}

resource "google_compute_subnetwork" "kube-subnet-with-private-ip" {
  name                    = "kube-subnet"
  ip_cidr_range           = "10.240.0.0/24"
  network                 = google_compute_network.kube-network.self_link


}


resource "google_compute_firewall" "default-internal" {
  name    = "kube-firewall-internal"
  network = google_compute_network.kube-network.name

  allow {
    protocol = "icmp"
  }
  allow {
    protocol  = "udp"
  } 
  allow {
    protocol = "tcp" 
  }

  source_tags = ["internal-kube-firewalls"]
  source_ranges = ["10.240.0.0/24","10.200.0.0/16"]
}
 


resource "google_compute_firewall" "default-external" {
  name    = "kube-firewall-external"
  network = google_compute_network.kube-network.name

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp" 
    ports    = ["22", "6443"]
  }

  source_tags = ["external-kube-firewalls"]
  source_ranges = ["0.0.0.0/0"]
}
 


 
data "google_compute_image" "debian_image" {
  family  = "ubuntu-1804-lts"
  project = "ubuntu-os-cloud"
  
    
}



# This section setup connections that will allow kubes workers
# to connect to the internet
# Achieved by :- 
#  - Setting up cloud router
#  - connected to natting device
#  - 1 static ip
# 
resource "google_compute_router" "router" {
  name = "router"
  region = "us-west1"
  network = google_compute_network.kube-network.self_link
  bgp {
    asn = 64514
  }
}
# only static ip per region (limit with free tier)

## This static ip is used for both worker and controller
resource "google_compute_address" "kube-component-external-ip" {

  name = "kube-component-ipv4"
}
# note: project's region is used
resource "google_compute_router_nat" "kube-env-nat" {
  name  = "nat-1"
  router = google_compute_router.router.name
 
  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips  = google_compute_address.kube-component-external-ip[*].self_link
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name = google_compute_subnetwork.kube-subnet-with-private-ip.self_link
     source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    filter = "ALL"
    enable = true
  }
}

############### End of NAT configurations #############

 


resource "google_compute_instance" "kube-controller" {

  count           = var.controller_count

  name            = "kube-controller-${count.index}"
  machine_type    = "n1-standard-1"
  tags            = ["kubernetes", "controller"]
  zone            =  data.google_compute_zones.available.names[count.index]
  boot_disk {
      initialize_params{
          image = data.google_compute_image.debian_image.self_link
          size = 200
      }
  }

      can_ip_forward = true

  network_interface {
      subnetwork =  google_compute_subnetwork.kube-subnet-with-private-ip.self_link
      
      network_ip        =  "10.240.0.1${count.index}"
    
  }

  metadata = {
    sshKeys = "kube-controller-${count.index}:${tls_private_key.controller-ssh-keys[count.index].public_key_openssh}"
    
  }
  service_account {
    scopes = ["compute-rw","storage-ro","service-management","service-control","logging-write","monitoring" ]
  }

}
resource "google_compute_instance" "kube-worker" {
  
  count           = var.controller_count

  name            = "kube-worker-${count.index}"
  machine_type    = "n1-standard-1"
  tags            = ["kubernetes", "worker"]
  zone            = data.google_compute_zones.available.names[count.index]
  boot_disk {
      initialize_params{
          image = data.google_compute_image.debian_image.self_link
          size = 200
      }
  }

      can_ip_forward = true

  network_interface {
      subnetwork =  google_compute_subnetwork.kube-subnet-with-private-ip.self_link
      
      network_ip        =  "10.240.0.2${count.index}"
     
  }
  metadata =  { 
    
    pod-cidr = "10.200.${count.index}.0/24" 
    sshKeys = "kube-worker-${count.index}:${tls_private_key.work-ssh-keys[count.index].public_key_openssh}"

  }
   
  service_account {
    scopes = ["compute-rw","storage-ro","service-management","service-control","logging-write","monitoring" ]
  }


}





# ################################################################
# #
# #     Bastion  configuration
# #
# #
# ###############################################################

# # Its going to reside in the same project and zone - however, its global

resource "google_compute_network" "bastion-network" {
  name                    = "bastion-network"
  description             = "bastion tools and servers will reside here"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "bastion-subnet-with-private-ip" {
  name                    = "bastion-subnet"
  ip_cidr_range           = "10.241.0.0/24"
  network                 = google_compute_network.bastion-network.self_link
  region                = "us-west2"

} 


####### Peering to connect kube and bastion VPCs 

resource "google_compute_network_peering" "peering1" {
  name = "peering1"
  network = google_compute_network.bastion-network.self_link
  peer_network = google_compute_network.kube-network.self_link
}

resource "google_compute_network_peering" "peering2" {
  name = "peering2"
  network = google_compute_network.kube-network.self_link
  peer_network = google_compute_network.bastion-network.self_link
}

############## END of VPC peering configuration ########

resource "google_compute_address" "bastion-ip" {
  name = "bastion-tool"
  region ="us-west2"
}

output "bastion-tool-ip" {
  value = google_compute_address.bastion-ip.address
}


resource "google_compute_firewall" "bastion-external" {
  name    = "bastion-firewall-external"
  network = google_compute_network.bastion-network.name

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp" 
    ports    = ["22", "6443"]
  }

  source_tags = ["external-kube-firewalls"]
  source_ranges = ["0.0.0.0/0"]
}
 


resource "google_compute_instance" "bastion" {
  
  name            = "bastion"
  machine_type    = "g1-small"
  tags            = ["ansible", "bastion", "automation"]
  zone            = "us-west2-a"
  
  boot_disk {
      initialize_params{
          image = data.google_compute_image.debian_image.self_link
          size = 50
      }
  }

      can_ip_forward = true

  network_interface {
    subnetwork =  google_compute_subnetwork.bastion-subnet-with-private-ip.self_link
    
    network_ip        =  "10.241.0.10"
    access_config {
      nat_ip =  google_compute_address.bastion-ip.address
    }
  }
  metadata =  { 
    
     
    sshKeys = "bastion:${tls_private_key.bastion-ssh-key.public_key_openssh}"
    
  }
   
  service_account {
    scopes = ["compute-rw","storage-ro","service-management","service-control","logging-write","monitoring" ]
  }

}

######## Load balancer config#####



resource "google_compute_http_health_check" "kubernetes-hc" {
  name               = "kubernetes-hc"
  description        = "Kubernetes Health Check" 
  request_path       = "/healthz"
  host               = "kubernetes.default.svc.cluster.local"
  
}

resource "google_compute_target_pool" "kube-controller-pool" {
  name = "kube-controller-pool"
  instances = google_compute_instance.kube-controller.*.self_link

  health_checks = [
    google_compute_http_health_check.kubernetes-hc.name
  ]
}

resource "google_compute_firewall" "allow-health-check" {
  name    = "allow-health-check"
  network = google_compute_network.kube-network.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp" 
  }

  source_tags = ["health-checks"]

  source_ranges = ["209.85.152.0/22","209.85.204.0/22", "35.191.0.0/16"]
}


resource "google_compute_forwarding_rule" "default" {
  # provider = "google-beta"
  name  = "kubernetes-forwarding-rule"
  port_range = "6443"
  target     = google_compute_target_pool.kube-controller-pool.self_link
  network_tier = "STANDARD"
}




###########################################################################################
#                       Provisioning Pod Network Routes
#
############################################################################################
resource "google_compute_route" "pod-routes" {
   count = length(google_compute_instance.kube-worker)

  name        = "kubernetes-route-10-200-${count.index}-0-24"
  dest_range  = "10.200.${count.index}.0/24"
  network     = google_compute_network.kube-network.name
  next_hop_ip = "10.240.0.2${count.index}"
  priority    = 1000
}


output "kube-public-ip" {
  value = google_compute_forwarding_rule.default.ip_address
}

output "nat-ip" {
  value = google_compute_address.kube-component-external-ip.address
}

 

 