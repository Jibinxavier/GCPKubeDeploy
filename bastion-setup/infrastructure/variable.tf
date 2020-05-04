variable "ssh_dir" {
   default  = "../ssh_keys/"
}

variable "automation_pub_key_file" {
   default  = "../ssh_keys/bastion.pub"
}

variable "worker_count" {
   default = 3
}
variable "controller_count" {
   default = 3
}