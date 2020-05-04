#!/usr/bin/env bash

# Build the environment
cd infrastructure
# Step 1 use terraform initialise the cluster
terraform apply --auto-approve

# terraform apply

# Step 2, use python script in bootstrap_hosts  to initialise the host file

cd ..
python populate_hosts.py --tf_state infrastructure/terraform.tfstate --ansible_inv ./inventories/production/hosts.yaml  --ssh_dir ./ssh_keys --json_v roles/configGeneration/files/

# Step 3 Use host file to setup bastion server and use local ansible  to 
# initialise the cluster

ansible-playbook bootstrap-automation-serv.yml --inventory=inventories


# Step 4, ssh into the automation server then run the cert generation playbook
#/inventories/production/hosts.yaml to get the IP address

# ssh -i ssh_keys/bastion bastion@<ip>

# Step 5, once logged in

cd /automation

ansible-playbook tlscertGenAndTransfer.yml --inventory=inventories 

ansible-playbook configure-cluster.yml --inventory=inventories

# to run together
#ansible-playbook tlscertGenAndTransfer.yml --inventory=inventories && ansible-playbook configure-cluster.yml --inventory=inventories


