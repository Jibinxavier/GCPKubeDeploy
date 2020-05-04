"""
    Populates the hosts file for Ansible
    There are couple of different approaches
    
    * Use Google APIs to retrieve the vm info
    * Or extract the information from Terraform state file

    This module implements the latter
    
    Following example is using the API
        import googleapiclient.discovery
        from google.oauth2 import service_account
        credentials = service_account.Credentials.from_service_account_file(
                            creds_file)
        compute = googleapiclient.discovery.build('compute', 'v1',credentials=credentials)
        
        result = compute.instances().list(project="distributedfilesystem",zone="us-west1").execute()
    
"""
 
import sys
import json
import pyaml
import argparse
import os
import glob
import re
def extract_categories(hosts):
    """
        Returns the hostname groupings
        it assumes hosts are named with following convention
        entity-name-<id>

        returns: [ entities]
    """
    mapped = {}
    for host in hosts:

        category = host.rsplit("-",1)[0]
       
        mapped[host] =category
     
    return mapped

def populate_host_files(ip_host_mappings,ssh_key_dir, dest_file):
    """ 
        ip_host_mappings: dict of mappings
        dest_file       : file path in string
        Notes: 
            * SSH keys- the private ssh keys paths probably should 
            match the jumphost/bastion server, therefore not populating here
    """

    mapped_cat = extract_categories(ip_host_mappings.keys())
     


    host_file = {"children":{}}
    
    for host,category in mapped_cat.items():

        for ip in ip_host_mappings[host]["private_ips"]:
            key = category + "-private"
            if key not in host_file["children"]:
                host_file["children"][category + "-private"]= {"hosts": {}} 
            key_file = os.path.join(ssh_key_dir,host)
            host_file["children"][category + "-private"]["hosts"][host] = {"ansible_port": 22, "ansible_host": ip,
                                                                "ansible_ssh_private_key_file":  key_file,
                                                                "ansible_ssh_extra_args":'-o StrictHostKeyChecking=no'
                                                                
                                                                }

         
        for ip in ip_host_mappings[host]["pub_ips"]:
            # initialise host so that it doesn't throw a key error
            key = category + "-public"
            if key not in host_file["children"]:
                host_file["children"][category + "-public"] = {"hosts": {}} 

            key_file = os.path.join(ssh_key_dir,host)
            
            host_file["children"][category + "-public"]["hosts"][host+"_pub"] =  {"ansible_port": 22, "ansible_host": ip,
                                                                 "ansible_ssh_private_key_file":  key_file}

    host_file = {"all" : host_file}
    with open (dest_file, "w") as f:
        pyaml.dump(host_file, f, vspacing=[2, 1])

def extract_host_ip_pairs_from(data):

    h_pairs = {}

    
  
    for resource in data["resources"]:
        if resource["type"] == "google_compute_instance":
             
            for inst in resource["instances"]:
               
                m_name = inst["attributes"]["name"]
                h_pairs[m_name] = {"pub_ips": [], "private_ips": []}

                for net_interface in inst["attributes"]["network_interface"]:
                    pub_ip = ""
                    if "access_config" in net_interface:
                        for item in net_interface["access_config"]:
                            h_pairs[m_name]["pub_ips"].append(item["nat_ip"])
                        
                    h_pairs[m_name]["private_ips"].append(net_interface["network_ip"])

                    

    return h_pairs

def validate_ssh_dir(ssh_dir):
    """
        Basic check:- directory exists and at least a pub key
    """
    
    valid = os.path.exists(ssh_dir) and any(glob.glob(ssh_dir + "/*"))

    if not valid:
        print("*"*10)
        print("Error: \"{}\" dir doesn't exist or no keys found".format(ssh_dir))
        print("*"*10)

        sys.exit(1)
def extract_ip_from_output(tf_state_f_data):
    """ Extracts ip address from keys that are suffixed
        with *-ip"
    """
    to_be_stored = {}
    all_outputs = tf_state_f_data["outputs"]
    for k in all_outputs:
        if re.search(".*-ip", k):
            to_be_stored[k] = all_outputs[k]["value"]
    return to_be_stored
def write_ip_mappings(ip_pairs, path):
    loc = os.path.join(path, "ip_pairs.json")
    with open(loc, "w+") as f:
        json.dump(ip_pairs, f)

def main(tf_state_file, ssh_dir, host_file_dst, json_version_dst):
    validate_ssh_dir(ssh_dir)
    with open(tf_state_file) as f:
        tf_state_f_data = json.load(f)

    pairs = extract_host_ip_pairs_from(tf_state_f_data)
    additional_pairs = extract_ip_from_output(tf_state_f_data)

   
    
    populate_host_files(pairs, ssh_dir, host_file_dst)
    # to append the additional pairs 
    pairs = pairs.copy()
    pairs.update(additional_pairs)
    write_ip_mappings(pairs,json_version_dst)



if __name__== "__main__":
    parser = argparse.ArgumentParser(
        description="Extracts public and internal IPs from a Terraform state file and populates Ansible inventory"
       )
    parser.add_argument('--tf_state', help='Terraform state file',  required=True)
    parser.add_argument('--ansible_inv', help='Path where the host file to be written',  required=True)
    parser.add_argument('--ssh_dir', help='SSH key location',  required=True)
    parser.add_argument('--json_v', help='location to store the jsonfied version',  required=True )
    args = parser.parse_args()
    main(args.tf_state, args.ssh_dir, args.ansible_inv, args.json_v)

    


