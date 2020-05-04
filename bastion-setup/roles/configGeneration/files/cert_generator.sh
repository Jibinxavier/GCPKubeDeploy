#!/usr/bin/env bash 
set -euo pipefail
# Generates certs for kube components using cfssl and cfssljson
#  Admin,Kubelet clients
# TODO:
#   Add the kubernetes public IP into the 
#----------------------------------------------------------------------------

force_recreate_=0

IP_PAIRS=""
CERT_DIR="CertDir"

mkdir -p "$CERT_DIR" # create if doesn

cd "$CERT_DIR" # <- working directory

print_usage() {
  printf "Usage:  -i: absolute path to json file contain IP adders REQUIRED
                  -f: force re-create the certs including CA
        "
}

while getopts 'i:f' flag; do
  case "${flag}" in
    i ) IP_PAIRS="${OPTARG}" ;; # as the working directory is "$CERT_DIR"
    f ) force_recreate_=1 ;;
    
    \? ) print_usage
       exit 1 ;;
  esac
done
echo $IP_PAIRS
if [ "$IP_PAIRS" = "" ]; then 

  print_usage 
  exit 1 
fi 

function validateTools {

  for tool in  cfssl cfssljson jq; do 

    if ! [ -x "$(command -v $tool)" ]; then
    echo "Error: $tool is not installed." >&2
    exit 1
    fi
  done
}




RED='\033[0;31m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


function generateCert { 
    local cn_="$1" 
    local kube_component_type_="$2"
    local csr_="$3" # the json file
    local function_call_="$4"  
    local force_recreate_="$5"
 

    local key_="$(cut -d '-' -f 1 <<< "$csr_")-key.pem"
    local cert_="$(cut -d '-' -f 1 <<< "$csr_").pem"

    
    # if csr not found or if its force recreate
    if [  "$force_recreate_" -eq 1 ] || [ ! -f "$csr_" ]; then
        buildCSR "$cn_" "$kube_component_type_" "$csr_"
    fi

    if [[  "$force_recreate_" -eq 1 ]]  || [[ ! -f "$key_" ]] || [[ ! -f "$cert_" ]] ; then
        output_="$(eval $function_call_)"
        retVal=$?
        if [ $retVal -ne 0  ]; then 
          echo 
          echo -e "${RED} ${cn_} cert creation failed!${NC}"
          echo 
          echo -e "${ORANGE}CMD used: $function_call_  ${NC}"
          echo 
          
        else
          echo
          echo "Succesfully created cert for: $cn_"
          echo
        fi
         
    fi  




}
function buildCSR {
    local cn_="$1"  
    local kube_component_type_="$2"
    local file_dest_="$3"
    
    local format='
    {
        "CN": "%s",
        "key": {
            "algo": "rsa",
            "size": 2048
        },
        "names": [
            {
            "C": "US",
            "L": "Portland",
            "O": "%s",
            "OU": "Kubernetes The Hard Way",
            "ST": "Oregon"
            }
        ]
    }
    '
    printf "$format"  "$cn_" "$kube_component_type_" > "$file_dest_"
   
}
########################################################
#   Create a Certificate Authority
#
########################################################
function buildCA {
    if [ ! -f ca-config.json  ] || [ ! -f  ca-csr.json ]; then
    cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}
EOF
        if [ ! -f ca-key.pem ] || [ ! -f ca.pem ]; then


            cfssl gencert -initca ca-csr.json | cfssljson -bare ca

        else
            echo "Nothing to do... CA key and Cert are generated"
            
        fi
    fi
}
############################################################
############################################################
############################################################
############################################################
#
#     END OF functions
#
############################################################
############################################################
############################################################
############################################################


validateTools
buildCA


########################################################
#   Client and Server Certificates
#  
########################################################
#--------------------------------------------------------
#   - Admin Client Certificate
#--------------------------------------------------------
echo -e "\n${BLUE} Admin Client Certificate${NC}"
cmd="cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin"
generateCert "admin" "system:masters" "admin-csr.json" "$cmd" "$force_recreate_"

#--------------------------------------------------------
#   - Kubelet Client Certificate
#--------------------------------------------------------
echo -e "\n${BLUE}Kubelet Client Certificate${NC}"
kube_workers=$(jq -r 'keys[]| select(contains("kube-worker"))' $IP_PAIRS)
 
for instance in $kube_workers; do
  
  jq_filter='.["'"${instance}"'"]|add|@csv'
  # hostnames could include the public and private ips
  hostnames="$( jq   -r  $jq_filter $IP_PAIRS)"

  cmd="cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${instance},${hostnames} \
  -profile=kubernetes \
  ${instance}-csr.json | cfssljson -bare ${instance}"

   
  generateCert "system:node:${instance}" "system:nodes" "${instance}-csr.json" "$cmd" "$force_recreate_"


done

########################################################
#   The Controller Manager Client Certificate
#  
########################################################
echo -e "\n${BLUE}Controller Manager Client Certificate${NC}"


cmd="cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager"

generateCert "system:kube-controller-manager" "system:kube-controller-manager" "kube-controller-manager-csr.json" "$cmd" "$force_recreate_"



########################################################
#   The Kube Proxy Client Certificate
#  
########################################################
echo -e "\n${BLUE}Kube Proxy Client Certificate${NC}"


cmd="cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy"

generateCert "system:kube-proxy" "system:node-proxier" "kube-proxy-csr.json" "$cmd" "$force_recreate_"


########################################################
#   The Scheduler Client Certificate
#  
########################################################
echo -e "\n${BLUE}Scheduler Client Certificate${NC}"

cmd="cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler"

generateCert "system:kube-scheduler" "system:kube-scheduler" "kube-scheduler-csr.json" "$cmd" "$force_recreate_"



########################################################
#   The Kubernetes API Server Certificate
#   
########################################################

 
echo -e "\n${BLUE}Kubernetes API Server${NC}"

node_type="controller"
jq_filter='with_entries(select(.key|match("'"${node_type}"'")))|map(add)|flatten|@csv'
controller_ips="$(cat $IP_PAIRS| jq   -r  $jq_filter)"
kube_public_ip="$(cat  $IP_PAIRS | jq -r '.["kube-public-ip"]' )" # jq can't do jq .kube-public-ip
########################
###########################
##### NOTE: the IPs are hard code in 
######################## https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/04-certificate-authority.md
 
KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local


cmd="cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.32.0.1,${controller_ips},127.0.0.1,${kube_public_ip},${KUBERNETES_HOSTNAMES} \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes"

generateCert "kubernetes" "Kubernetes" "kubernetes-csr.json" "$cmd" "$force_recreate_"



########################################################
#   The Service Account Key Pair
#   
########################################################

echo -e "\n${BLUE} Service Account ${NC}"
pwd

cmd="cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account"
generateCert "service-accounts" "Kubernetes" "service-account-csr.json" "$cmd" "$force_recreate_"






echo " chmod  644 ./* To ensure that ansible is able at least read the pem keys"
chmod  644 ./*

