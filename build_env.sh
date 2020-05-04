#!/usr/bin/env bash

# Build the environment
cd infrastructure
# Step 1 use terraform initialise the cluster
terraform apply --auto-approve

# terraform apply

# Step 2, use python script in bootstrap_hosts  to initialise the host file

cd ..
python populate_hosts.py --tf_state infrastructure/terraform.tfstate --ansible_inv ./inventories/production/hosts.yaml  --ssh_dir ./ssh_keys --json_v roles/configGeneration/files/

# Step 3 Use host file to setup ansible server and before that use local ansible server to 
# initialise the ansible server

ansible-playbook bootstrap-automation-serv.yml --inventory=inventories


# Step 4, ssh into the automation server then run the cert generation playbook
#/home/jibin/workspace/gcp/kube_impl/bastion-setup/inventories/production/hosts.yaml to get the IP address

# ssh -i /home/jibin/workspace/gcp/kube_impl/bastion-setup/ssh_keys/bastion bastion@34.94.223.244

# Step 5, once logged in

cd /automation

ansible-playbook tlscertGenAndTransfer.yml --inventory=inventories 

ansible-playbook configure-cluster.yml --inventory=inventories

# to run together
#ansible-playbook tlscertGenAndTransfer.yml --inventory=inventories && ansible-playbook configure-cluster.yml --inventory=inventories


#openssl s_client -connect 10.240.0.10:2379 -CAfile      
# cat /dev/null > /home/jibin/.ssh/known_hosts

 sudo tcpdump -i wlp2s0 -nn -s0 -v dst 34.94.197.122

    ssh -i /automation/ssh_keys/kube-controller-0  kube-controller-0@10.240.0.10