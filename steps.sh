# Variables
RESOURCE_GROUP="aks-network-policies"
LOCATION="westeurope"
AKS_NAME="aks-network-policies"
AKS_VNET="aks-vnet"
AKS_SUBNET="aks-subnet"

# Create resource group
az group create \
--name $RESOURCE_GROUP \
--location $LOCATION

# Create VNET
az network vnet create \
--resource-group $RESOURCE_GROUP \
--name $AKS_VNET \
--address-prefixes 10.0.0.0/8 \
--subnet-name $AKS_SUBNET \
--subnet-prefixes 10.240.0.0/24

# Create a service principal and read in the application ID
SP=$(az ad sp create-for-rbac --output json)
SP_ID=$(echo $SP | jq -r .appId)
SP_PASSWORD=$(echo $SP | jq -r .password)

# Wait 15 seconds to make sure that service principal has propagated
echo "Waiting for service principal to propagate..."
sleep 15

# Get the virtual network resource ID
VNET_ID=$(az network vnet show --resource-group $RESOURCE_GROUP --name $AKS_VNET --query id -o tsv)

# Assign the service principal Contributor permissions to the virtual network resource
az role assignment create --assignee $SP_ID --scope $VNET_ID --role Contributor

# Get the virtual network subnet resource ID
SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $AKS_VNET --name $AKS_SUBNET --query id -o tsv)

# Create AKS cluster
az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_NAME \
    --generate-ssh-keys \
    --docker-bridge-address 172.17.0.1/16 \
    --dns-service-ip 10.2.0.10 \
    --service-cidr 10.2.0.0/24 \
    --vnet-subnet-id $SUBNET_ID \
    --service-principal $SP_ID \
    --client-secret $SP_PASSWORD \
    --network-plugin azure \
    --network-policy azure

# Get AKS cluster credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME

# Create tour of heroes app
k create ns tour-of-heroes 
k apply -f tour-of-heroes -n tour-of-heroes --recursive

watch kubectl get pod -n tour-of-heroes
k get svc -n tour-of-heroes

# Get public IP address of tour-of-heroes-web service
FRONT_END_IP=$(kubectl get svc tour-of-heroes-web -n tour-of-heroes -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# Check if the service is up
curl http://$FRONT_END_IP

API_IP=$(kubectl get svc tour-of-heroes-api -n tour-of-heroes -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# API
curl https://$API_IP/api/values

# Apply network policies
kubectl apply -f network-policies/ -n tour-of-heroes
k get netpol -n tour-of-heroes
k describe netpol allow-api-call-sql -n tour-of-heroes
k describe netpol allow-web-call-api -n tour-of-heroes

# Create a new front-end in a different namespace pointing to the same service
k create ns tour-of-heroes-two
k apply -f tour-of-heroes/frontend-in-a-different-ns -n tour-of-heroes-two

watch kubectl get pods -n tour-of-heroes-two
k get svc -n tour-of-heroes-two

# Execute alpine in a pod for testing
kubectl run test-$RANDOM --rm -i --tty --image=alpine -n tour-of-heroes-two -- sh
wget -qO- --timeout=2 http://tour-of-heroes-web # Success
wget -qO- --timeout=2 http://tour-of-heroes-api.tour-of-heroes # Timeout
