#!/usr/bin/env bash

# ============================================================
# TechCrush RouteWell
# Multi-Tier Azure VNet Deployment
# ============================================================
#
# Architecture:
#
# Internet
#    |
#    v
# Web VM
#    |
#    v
# App VM
#    |
#    v
# DB VM
#
# VNet:
#   10.10.0.0/16
#
# Subnets:
#   Web: 10.10.0.0/27
#   Reserved: 10.10.0.32/27
#   App: 10.10.0.64/26
#   DB: 10.10.0.128/28
#
# VM SKU:
#   Standard_DS1_v2
#
# Total vCPUs:
#   Web = 1
#   App = 1
#   DB  = 1
#   ----------
#   Total = 3
#
# Regional quota discovered:
#   4 vCPUs
#
# Security:
#   Standard
#
# IMPORTANT:
#   This script assumes the Azure feature:
#
#   Microsoft.Compute/UseStandardSecurityType
#
#   has been registered.
#
# ============================================================

set -o pipefail

# ============================================================
# CONFIGURATION
# ============================================================

DEFAULT_RESOURCE_GROUP="routewell-rg"
DEFAULT_LOCATION="southafricanorth"
DEFAULT_ADMIN_USERNAME="routewelladmin"

VNET_NAME="routewell-vnet"

WEB_SUBNET_NAME="web-subnet"
RESERVED_SUBNET_NAME="reserved-subnet"
APP_SUBNET_NAME="app-subnet"
DB_SUBNET_NAME="db-subnet"

WEB_NSG_NAME="web-nsg"
APP_NSG_NAME="app-nsg"
DB_NSG_NAME="db-nsg"

WEB_VM_NAME="routewell-web-vm"
APP_VM_NAME="routewell-app-vm"
DB_VM_NAME="routewell-db-vm"

VM_IMAGE="Ubuntu2204"

# Proven to successfully deploy in South Africa North
VM_SIZE="Standard_DS1_v2"

# Explicitly use Standard security.
# This prevents:
#
# --security-type None
#
# which caused the previous deployment failure.
SECURITY_TYPE="Standard"

SSH_PUBLIC_KEY="$HOME/.ssh/id_ed25519.pub"

# ============================================================
# NETWORK CIDRs
# ============================================================

VNET_CIDR="10.10.0.0/16"

WEB_CIDR="10.10.0.0/27"
RESERVED_CIDR="10.10.0.32/27"
APP_CIDR="10.10.0.64/26"
DB_CIDR="10.10.0.128/28"

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# HELPER FUNCTIONS
# ============================================================

print_header() {
    echo ""
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

print_section() {
    echo ""
    echo "--------------------------------------------"
    echo "$1"
    echo "--------------------------------------------"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

fail() {
    echo ""
    echo -e "${RED}ERROR: $1${NC}"
    echo ""
    exit 1
}

# ============================================================
# START
# ============================================================

clear 2>/dev/null || true

print_header "TechCrush RouteWell Multi-Tier VNet Deployment"

echo ""
echo "This script will deploy:"
echo ""
echo "  Resource Group : $DEFAULT_RESOURCE_GROUP"
echo "  Region         : $DEFAULT_LOCATION"
echo "  VNet           : $VNET_NAME"
echo ""
echo "  Web VM         : $WEB_VM_NAME"
echo "  App VM         : $APP_VM_NAME"
echo "  DB VM          : $DB_VM_NAME"
echo ""
echo "  VM Image       : $VM_IMAGE"
echo "  VM Size        : $VM_SIZE"
echo "  Security Type  : $SECURITY_TYPE"
echo ""
echo "The deployment uses 3 vCPUs total."
echo ""
echo "Continue? [y/N]"

read -r CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Deployment cancelled."
    exit 0
fi

# ============================================================
# USER INPUT
# ============================================================

echo ""

read -r -p "Enter Resource Group Name [$DEFAULT_RESOURCE_GROUP]: " INPUT_RG

if [[ -n "$INPUT_RG" ]]; then
    RESOURCE_GROUP="$INPUT_RG"
else
    RESOURCE_GROUP="$DEFAULT_RESOURCE_GROUP"
fi

read -r -p "Enter Azure Region [$DEFAULT_LOCATION]: " INPUT_LOCATION

if [[ -n "$INPUT_LOCATION" ]]; then
    LOCATION="$INPUT_LOCATION"
else
    LOCATION="$DEFAULT_LOCATION"
fi

read -r -p "Enter Admin Username [$DEFAULT_ADMIN_USERNAME]: " INPUT_USERNAME

if [[ -n "$INPUT_USERNAME" ]]; then
    ADMIN_USERNAME="$INPUT_USERNAME"
else
    ADMIN_USERNAME="$DEFAULT_ADMIN_USERNAME"
fi

# ============================================================
# DISPLAY CONFIGURATION
# ============================================================

print_section "Deployment Configuration"

echo "Resource Group     : $RESOURCE_GROUP"
echo "Azure Region       : $LOCATION"
echo "VNet               : $VNET_NAME"
echo "VNet CIDR          : $VNET_CIDR"
echo ""
echo "Web CIDR            : $WEB_CIDR"
echo "Reserved CIDR       : $RESERVED_CIDR"
echo "App CIDR            : $APP_CIDR"
echo "DB CIDR             : $DB_CIDR"
echo ""
echo "Admin Username      : $ADMIN_USERNAME"
echo "VM Image            : $VM_IMAGE"
echo "VM Size             : $VM_SIZE"
echo "Security Type       : $SECURITY_TYPE"
echo ""
echo "SSH Public Key      : $SSH_PUBLIC_KEY"

echo ""

read -r -p "Continue with deployment? [y/N]: " CONFIRM_DEPLOY

if [[ ! "$CONFIRM_DEPLOY" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Deployment cancelled."
    exit 0
fi

# ============================================================
# CHECK AZURE CLI
# ============================================================

print_section "Checking Azure CLI"

if ! command_exists az; then
    fail "Azure CLI is not installed or not available in PATH."
fi

echo -e "${GREEN}Azure CLI found.${NC}"

# ============================================================
# CHECK AZURE LOGIN
# ============================================================

print_section "Checking Azure Login"

if ! az account show >/dev/null 2>&1; then

    echo -e "${YELLOW}You are not logged into Azure.${NC}"
    echo ""
    echo "Run:"
    echo ""
    echo "  az login"
    echo ""

    exit 1

fi

AZURE_ACCOUNT=$(az account show --query "user.name" --output tsv 2>/dev/null)
AZURE_SUBSCRIPTION=$(az account show --query "name" --output tsv 2>/dev/null)
AZURE_SUBSCRIPTION_ID=$(az account show --query "id" --output tsv 2>/dev/null)

echo "Azure Account      : $AZURE_ACCOUNT"
echo "Azure Subscription : $AZURE_SUBSCRIPTION"
echo "Subscription ID    : $AZURE_SUBSCRIPTION_ID"

# ============================================================
# CHECK SSH KEY
# ============================================================

print_section "Checking SSH Public Key"

if [[ ! -f "$SSH_PUBLIC_KEY" ]]; then
    fail "SSH public key not found at $SSH_PUBLIC_KEY"
fi

echo -e "${GREEN}SSH public key found.${NC}"

# ============================================================
# CHECK AZURE REGION
# ============================================================

print_section "Checking Azure Region"

REGION_EXISTS=$(az account list-locations --query "[?name=='$LOCATION'] | length(@)" --output tsv 2>/dev/null)

if [[ "$REGION_EXISTS" != "1" ]]; then
    fail "Azure region '$LOCATION' was not found."
fi

echo -e "${GREEN}Region '$LOCATION' is valid.${NC}"

# ============================================================
# CHECK STANDARD SECURITY TYPE FEATURE
# ============================================================

print_section "Checking Standard Security Type Support"

echo "Checking Microsoft.Compute/UseStandardSecurityType..."

FEATURE_STATE=$(az feature show --namespace Microsoft.Compute --name UseStandardSecurityType --query "properties.state" --output tsv 2>/dev/null)

if [[ "$FEATURE_STATE" == "Registered" ]]; then

    echo -e "${GREEN}UseStandardSecurityType feature is Registered.${NC}"

else

    echo -e "${YELLOW}Feature state: ${FEATURE_STATE:-Unknown}${NC}"

    echo ""
    echo "Attempting to register the feature..."

    az feature register --namespace Microsoft.Compute --name UseStandardSecurityType --output none 2>/dev/null || true

    echo ""
    echo "Refreshing Microsoft.Compute provider registration..."

    az provider register --namespace Microsoft.Compute --output none 2>/dev/null || true

    echo ""
    echo "Checking feature state again..."

    FEATURE_STATE=$(az feature show --namespace Microsoft.Compute --name UseStandardSecurityType --query "properties.state" --output tsv 2>/dev/null)

    if [[ "$FEATURE_STATE" != "Registered" ]]; then

        echo ""
        echo -e "${YELLOW}WARNING:${NC}"
        echo "The Standard security type feature is not yet Registered."
        echo ""
        echo "Current state:"
        echo "$FEATURE_STATE"
        echo ""
        echo "Azure may still allow deployment if the feature"
        echo "registration has propagated."
        echo ""
        echo "Continuing with deployment..."

    else

        echo -e "${GREEN}Feature is now Registered.${NC}"

    fi

fi

# ============================================================
# CHECK VM SKU
# ============================================================

print_section "Checking VM SKU Availability"

echo "Region : $LOCATION"
echo "SKU    : $VM_SIZE"

SKU_COUNT=$(az vm list-skus --location "$LOCATION" --resource-type virtualMachines --all --query "[?name=='$VM_SIZE'] | length(@)" --output tsv 2>/dev/null)

if [[ "$SKU_COUNT" == "0" ]]; then

    echo ""
    echo -e "${RED}ERROR: $VM_SIZE was not found in $LOCATION.${NC}"
    echo ""
    echo "The deployment cannot continue."
    exit 1

fi

echo -e "${GREEN}VM SKU exists in the selected region.${NC}"

# ============================================================
# CHECK RESOURCE GROUP
# ============================================================

print_section "Checking Resource Group"

RG_EXISTS=$(az group exists --name "$RESOURCE_GROUP" 2>/dev/null)

if [[ "$RG_EXISTS" == "true" ]]; then

    echo "Resource Group already exists."
    echo "Reusing: $RESOURCE_GROUP"

else

    echo "Creating Resource Group..."

    if az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table; then

        echo -e "${GREEN}Resource Group created successfully.${NC}"

    else

        fail "Failed to create Resource Group."

    fi

fi

# ============================================================
# CREATE VNET
# ============================================================

print_section "Checking Virtual Network"

VNET_EXISTS=$(az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --query "name" --output tsv 2>/dev/null)

if [[ "$VNET_EXISTS" == "$VNET_NAME" ]]; then

    echo "VNet already exists."
    echo "Reusing: $VNET_NAME"

else

    echo "Creating VNet..."

    if az network vnet create --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --location "$LOCATION" --address-prefixes "$VNET_CIDR" --output none; then

        echo -e "${GREEN}VNet created successfully.${NC}"

    else

        fail "Failed to create VNet."

    fi

fi

# ============================================================
# CREATE WEB SUBNET
# ============================================================

print_section "Checking Web Subnet"

WEB_SUBNET_EXISTS=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$WEB_SUBNET_NAME" --query "name" --output tsv 2>/dev/null)

if [[ "$WEB_SUBNET_EXISTS" == "$WEB_SUBNET_NAME" ]]; then

    echo "Web subnet already exists."

else

    echo "Creating Web subnet..."

    az network vnet subnet create --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$WEB_SUBNET_NAME" --address-prefixes "$WEB_CIDR" --output none || fail "Failed to create Web subnet."

    echo -e "${GREEN}Web subnet created.${NC}"

fi

# ============================================================
# CREATE RESERVED SUBNET
# ============================================================

print_section "Checking Reserved Subnet"

RESERVED_SUBNET_EXISTS=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$RESERVED_SUBNET_NAME" --query "name" --output tsv 2>/dev/null)

if [[ "$RESERVED_SUBNET_EXISTS" == "$RESERVED_SUBNET_NAME" ]]; then

    echo "Reserved subnet already exists."

else

    echo "Creating Reserved subnet..."

    az network vnet subnet create --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$RESERVED_SUBNET_NAME" --address-prefixes "$RESERVED_CIDR" --output none || fail "Failed to create Reserved subnet."

    echo -e "${GREEN}Reserved subnet created.${NC}"

fi

# ============================================================
# CREATE APP SUBNET
# ============================================================

print_section "Checking App Subnet"

APP_SUBNET_EXISTS=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$APP_SUBNET_NAME" --query "name" --output tsv 2>/dev/null)

if [[ "$APP_SUBNET_EXISTS" == "$APP_SUBNET_NAME" ]]; then

    echo "App subnet already exists."

else

    echo "Creating App subnet..."

    az network vnet subnet create --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$APP_SUBNET_NAME" --address-prefixes "$APP_CIDR" --output none || fail "Failed to create App subnet."

    echo -e "${GREEN}App subnet created.${NC}"

fi

# ============================================================
# CREATE DB SUBNET
# ============================================================

print_section "Checking DB Subnet"

DB_SUBNET_EXISTS=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$DB_SUBNET_NAME" --query "name" --output tsv 2>/dev/null)

if [[ "$DB_SUBNET_EXISTS" == "$DB_SUBNET_NAME" ]]; then

    echo "DB subnet already exists."

else

    echo "Creating DB subnet..."

    az network vnet subnet create --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$DB_SUBNET_NAME" --address-prefixes "$DB_CIDR" --output none || fail "Failed to create DB subnet."

    echo -e "${GREEN}DB subnet created.${NC}"

fi

# ============================================================
# CREATE WEB NSG
# ============================================================

print_section "Creating Network Security Groups"

if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$WEB_NSG_NAME" >/dev/null 2>&1; then

    echo "Web NSG already exists."

else

    echo "Creating Web NSG..."

    az network nsg create --resource-group "$RESOURCE_GROUP" --name "$WEB_NSG_NAME" --location "$LOCATION" --output none || fail "Failed to create Web NSG."

    echo "Web NSG created."

fi

# ============================================================
# WEB NSG RULES
# ============================================================

echo "Configuring Web NSG rules..."

az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$WEB_NSG_NAME" --name Allow-SSH --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges 22 --output none 2>/dev/null || true

az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$WEB_NSG_NAME" --name Allow-HTTP --priority 110 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges 80 --output none 2>/dev/null || true

az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$WEB_NSG_NAME" --name Allow-HTTPS --priority 120 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges 443 --output none 2>/dev/null || true

# ============================================================
# CREATE APP NSG
# ============================================================

if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$APP_NSG_NAME" >/dev/null 2>&1; then

    echo "App NSG already exists."

else

    echo "Creating App NSG..."

    az network nsg create --resource-group "$RESOURCE_GROUP" --name "$APP_NSG_NAME" --location "$LOCATION" --output none || fail "Failed to create App NSG."

    echo "App NSG created."

fi

# ============================================================
# APP NSG RULE
# ============================================================

echo "Configuring App NSG rules..."

az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$APP_NSG_NAME" --name Allow-App-From-Web --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "$WEB_CIDR" --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges 3000 5000 --output none 2>/dev/null || true

# ============================================================
# CREATE DB NSG
# ============================================================

if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$DB_NSG_NAME" >/dev/null 2>&1; then

    echo "DB NSG already exists."

else

    echo "Creating DB NSG..."

    az network nsg create --resource-group "$RESOURCE_GROUP" --name "$DB_NSG_NAME" --location "$LOCATION" --output none || fail "Failed to create DB NSG."

    echo "DB NSG created."

fi

# ============================================================
# DB NSG RULE
# ============================================================

echo "Configuring DB NSG rules..."

az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$DB_NSG_NAME" --name Allow-PostgreSQL-From-App --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "$APP_CIDR" --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges 5432 --output none 2>/dev/null || true

# ============================================================
# ASSOCIATE WEB NSG
# ============================================================

print_section "Associating NSGs with Subnets"

echo "Associating Web NSG..."

az network vnet subnet update --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$WEB_SUBNET_NAME" --network-security-group "$WEB_NSG_NAME" --output none || fail "Failed to associate Web NSG."

echo "Web NSG associated."

# ============================================================
# ASSOCIATE APP NSG
# ============================================================

echo "Associating App NSG..."

az network vnet subnet update --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$APP_SUBNET_NAME" --network-security-group "$APP_NSG_NAME" --output none || fail "Failed to associate App NSG."

echo "App NSG associated."

# ============================================================
# ASSOCIATE DB NSG
# ============================================================

echo "Associating DB NSG..."

az network vnet subnet update --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$DB_SUBNET_NAME" --network-security-group "$DB_NSG_NAME" --output none || fail "Failed to associate DB NSG."

echo "DB NSG associated."

# ============================================================
# VERIFY SUBNET NSGS
# ============================================================

print_section "Verifying NSG Associations"

WEB_NSG_CHECK=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$WEB_SUBNET_NAME" --query "networkSecurityGroup.id" --output tsv 2>/dev/null)

APP_NSG_CHECK=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$APP_SUBNET_NAME" --query "networkSecurityGroup.id" --output tsv 2>/dev/null)

DB_NSG_CHECK=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$DB_SUBNET_NAME" --query "networkSecurityGroup.id" --output tsv 2>/dev/null)

if [[ -z "$WEB_NSG_CHECK" ]]; then
    fail "Web NSG association could not be verified."
fi

if [[ -z "$APP_NSG_CHECK" ]]; then
    fail "App NSG association could not be verified."
fi

if [[ -z "$DB_NSG_CHECK" ]]; then
    fail "DB NSG association could not be verified."
fi

echo -e "${GREEN}All subnet NSG associations verified.${NC}"

# ============================================================
# CREATE WEB VM
# ============================================================

print_section "Creating Web VM"

echo "VM Name       : $WEB_VM_NAME"
echo "Subnet        : $WEB_SUBNET_NAME"
echo "Size          : $VM_SIZE"
echo "Security Type : $SECURITY_TYPE"

if az vm show --resource-group "$RESOURCE_GROUP" --name "$WEB_VM_NAME" >/dev/null 2>&1; then

    echo "Web VM already exists."
    echo "Skipping creation."

else

    if az vm create --resource-group "$RESOURCE_GROUP" --name "$WEB_VM_NAME" --location "$LOCATION" --image "$VM_IMAGE" --size "$VM_SIZE" --admin-username "$ADMIN_USERNAME" --ssh-key-values "$SSH_PUBLIC_KEY" --authentication-type ssh --security-type "$SECURITY_TYPE" --vnet-name "$VNET_NAME" --subnet "$WEB_SUBNET_NAME" --public-ip-sku Standard --output json; then

        echo -e "${GREEN}Web VM created successfully.${NC}"

    else

        echo -e "${RED}ERROR: Web VM creation failed.${NC}"
        echo ""
        echo "The deployment has stopped."
        echo ""
        echo "Resource Group has NOT been deleted."
        echo "You can inspect the failed deployment before retrying."

        exit 1

    fi

fi

# ============================================================
# CREATE APP VM
# ============================================================

print_section "Creating App VM"

echo "VM Name       : $APP_VM_NAME"
echo "Subnet        : $APP_SUBNET_NAME"
echo "Size          : $VM_SIZE"
echo "Security Type : $SECURITY_TYPE"

if az vm show --resource-group "$RESOURCE_GROUP" --name "$APP_VM_NAME" >/dev/null 2>&1; then

    echo "App VM already exists."
    echo "Skipping creation."

else

    if az vm create --resource-group "$RESOURCE_GROUP" --name "$APP_VM_NAME" --location "$LOCATION" --image "$VM_IMAGE" --size "$VM_SIZE" --admin-username "$ADMIN_USERNAME" --ssh-key-values "$SSH_PUBLIC_KEY" --authentication-type ssh --security-type "$SECURITY_TYPE" --vnet-name "$VNET_NAME" --subnet "$APP_SUBNET_NAME" --public-ip-address "" --output json; then

        echo -e "${GREEN}App VM created successfully.${NC}"

    else

        echo -e "${RED}ERROR: App VM creation failed.${NC}"
        echo ""
        echo "The Web VM was created successfully."
        echo "The App VM failed."
        echo ""
        echo "Resource Group has NOT been deleted."
        echo "Inspect the deployment before retrying."

        exit 1

    fi

fi

# ============================================================
# CREATE DB VM
# ============================================================

print_section "Creating DB VM"

echo "VM Name       : $DB_VM_NAME"
echo "Subnet        : $DB_SUBNET_NAME"
echo "Size          : $VM_SIZE"
echo "Security Type : $SECURITY_TYPE"

if az vm show --resource-group "$RESOURCE_GROUP" --name "$DB_VM_NAME" >/dev/null 2>&1; then

    echo "DB VM already exists."
    echo "Skipping creation."

else

    if az vm create --resource-group "$RESOURCE_GROUP" --name "$DB_VM_NAME" --location "$LOCATION" --image "$VM_IMAGE" --size "$VM_SIZE" --admin-username "$ADMIN_USERNAME" --ssh-key-values "$SSH_PUBLIC_KEY" --authentication-type ssh --security-type "$SECURITY_TYPE" --vnet-name "$VNET_NAME" --subnet "$DB_SUBNET_NAME" --public-ip-address "" --output json; then

        echo -e "${GREEN}DB VM created successfully.${NC}"

    else

        echo -e "${RED}ERROR: DB VM creation failed.${NC}"
        echo ""
        echo "Web VM and App VM may already exist."
        echo ""
        echo "Resource Group has NOT been deleted."
        echo "Inspect the deployment before retrying."

        exit 1

    fi

fi

# ============================================================
# FINAL VERIFICATION
# ============================================================

print_header "RouteWell Deployment Verification"

echo ""
echo "Virtual Network:"
az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --query "{Name:name,Location:location,AddressSpace:addressSpace.addressPrefixes}" --output table

echo ""
echo "Subnets:"
az network vnet subnet list --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --query "[].{Name:name,CIDR:addressPrefix}" --output table

echo ""
echo "Virtual Machines:"
az vm list --resource-group "$RESOURCE_GROUP" --show-details --query "[].{Name:name,Size:hardwareProfile.vmSize,PowerState:powerState,PrivateIP:privateIps,PublicIP:publicIps}" --output table

echo ""
echo "NSGs:"
az network nsg list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Location:location}" --output table

# ============================================================
# SUCCESS
# ============================================================

print_header "RouteWell Deployment Completed Successfully"

echo ""
echo -e "${GREEN}All RouteWell infrastructure has been deployed.${NC}"
echo ""
echo "Resource Group : $RESOURCE_GROUP"
echo "Region         : $LOCATION"
echo "VNet           : $VNET_NAME"
echo ""
echo "Web VM         : $WEB_VM_NAME"
echo "App VM         : $APP_VM_NAME"
echo "DB VM          : $DB_VM_NAME"
echo ""
echo "VM Size        : $VM_SIZE"
echo "Security Type  : $SECURITY_TYPE"
echo ""
echo "Architecture:"
echo ""
echo "  Internet"
echo "      |"
echo "      v"
echo "  Web VM"
echo "      |"
echo "      v"
echo "  App VM"
echo "      |"
echo "      v"
echo "  DB VM"
echo ""
echo "============================================================"
echo "Deployment Complete"
echo "============================================================"
echo ""