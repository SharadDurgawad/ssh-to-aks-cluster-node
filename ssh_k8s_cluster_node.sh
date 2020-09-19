########## This script is used to ssh the AKS kubernetes cluster nodes ##########
########## Author: Sharad Durgawad <durgawad@gmail.com>                ##########
########## Date: August 15 2020                                        ##########

#!/bin/bash

subscription_name=$1
resource_group_name=$2
cluster_name=$3
pod_name=$4
node_ip_address=$5

echo "$0 <subscription_name> <resource_group_name> <cluster_name> <pod_name> <node_ip_address>"
echo "Please run -> kubectl get nodes -o wide command to get the node internal IP address"

echo $1 $2 $3 $4 $5

# Create a ssh key pair

ssh-keygen -m PEM -t rsa -N "" -b 4096 -f ~/.ssh/id_rsa -q <<< y

if [ $? -eq 0 ]
then
  echo -e "\nssh key generated successfully"
else
  echo "Failed to generate ssh key"
  exit 1
fi

CLUSTER_RESOURCE_GROUP=$(az aks show --resource-group $resource_group_name --subscription $subscription_name --name $cluster_name --query nodeResourceGroup -o tsv)

if [ $CLUSTER_RESOURCE_GROUP ]
then
    echo "Cluster Resource Group: $CLUSTER_RESOURCE_GROUP"
else
    echo "Cluster Resource Group does not exist"
    exit 1
fi

SCALE_SET_NAME=$(az vmss list --resource-group $CLUSTER_RESOURCE_GROUP --subscription $subscription_name --query [0].name -o tsv)

if [ $SCALE_SET_NAME ]
then
    echo "Scale Set Name: $SCALE_SET_NAME"
else
    echo "Scale Set Name does not exist"
    exit 1
fi

az vmss extension set --resource-group $CLUSTER_RESOURCE_GROUP --subscription $subscription_name --vmss-name $SCALE_SET_NAME --name VMAccessForLinux --publisher Microsoft.OSTCExtensions --version 1.4 --protected-settings "{'username':'azureuser', 'ssh_key':'$(cat ~/.ssh/id_rsa.pub)'}"

az vmss update-instances --instance-ids '*' --resource-group $CLUSTER_RESOURCE_GROUP --subscription $subscription_name --name $SCALE_SET_NAME


kubectl run --generator=run-pod/v1 $pod_name --image=debian --restart=Never --command -- sleep 10000

if [ $? -eq 0 ]
then
  echo "Created pod: $pod_name"
else
  echo "Failed to create Pod $pod_name"
  exit 1
fi

# Install openssh client inside the pod
kubectl exec -it $pod_name -- bash -c "apt-get update > /dev/null; apt-get install openssh-client -y" > /dev/null
if [ $? -eq 0 ]
then
  echo "openssh client installed inside $pod_name pod"
else
  echo "openssh client install failed"
  exit 1
fi
# Copy private key inside pod at /id_rsa path
kubectl cp ~/.ssh/id_rsa $(kubectl get pod -l run=$pod_name -o jsonpath='{.items[0].metadata.name}'):/id_rsa
if [ $? -eq 0 ]
then
  echo "ssh key copy successful"
else
  echo "ssh key copy failed"
  exit 1
fi
# Update the permissions of file copied
kubectl exec -t $pod_name -- bash -c "chmod 0600 id_rsa"
if [ $? -eq 0 ]
then
  echo "set permission on ssh key file"
else
  echo "permissions failed"
  exit 1
fi
# SSH to the node from pod
kubectl exec -it $pod_name -- bash -c "ssh -o StrictHostKeyChecking=no -i id_rsa azureuser@$node_ip_address"

