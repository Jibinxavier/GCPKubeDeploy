# GCPKubeDeploy
This an attempt at building the a 3 worker and 3 controller environment based on https://github.com/kelseyhightower/kubernetes-the-hard-way, using Terraform and Ansible

# Usage

1. update "credentials" and "project"
1. `cd infrastructure`
1. `terraform plan`
1. `terraform apply`
1. Use python script in bootstrap_hosts to initialise the Ansible host file
`cd .. && python populate_hosts.py --tf_state infrastructure/terraform.tfstate --ansible_inv ./inventories/production/hosts.yaml  --ssh_dir ./ssh_keys --json_v roles/configGeneration/files/ `

1. Use host file to setup bastion server and deploy other components from there
`ansible-playbook bootstrap-automation-serv.yml --inventory=inventories`

1. SSH into bastion server `ssh -i ssh_keys/bastion bastion@<ip>`

1. `cd /automation`

1. `ansible-playbook tlscertGenAndTransfer.yml --inventory=inventories`

1. `ansible-playbook configure-cluster.yml --inventory=inventories`  
