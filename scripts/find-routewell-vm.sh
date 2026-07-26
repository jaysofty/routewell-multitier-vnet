#!/usr/bin/env bash

# ============================================================
# TechCrush RouteWell
# Azure Real VM Region + SKU Availability Tester
# ============================================================
#
# Purpose:
#
# Find a REGION + VM SKU combination that Azure can ACTUALLY
# provision for this subscription.
#
# RouteWell requires:
#
#   Web VM : 1 vCPU
#   App VM : 1 vCPU
#   DB VM  : 1 vCPU
#
# Total:
#
#   3 vCPUs
#
# IMPORTANT:
#
# This script tests ONE temporary VM at a time.
#
# It does NOT deploy RouteWell.
#
# It does NOT modify routewell-rg.
#
# It creates:
#
#   routewell-vm-test-rg
#
# Then it tries:
#
#   Region + SKU
#
# If successful:
#
#   VM is deleted.
#   Temporary resource group is deleted.
#   Working combination is displayed.
#
# If unsuccessful:
#
#   The error is recorded.
#   The script moves to the next combination.
#
# ============================================================

set -o pipefail

# ============================================================
# CONFIGURATION
# ============================================================

TEST_RESOURCE_GROUP="routewell-vm-test-rg"

ADMIN_USERNAME="routewelladmin"

SSH_PUBLIC_KEY="$HOME/.ssh/id_ed25519.pub"

VM_IMAGE="Ubuntu2204"

# Maximum time allowed for one VM deployment test.
#
# 10 minutes = 600 seconds.
#
# If Azure CLI hangs longer than this, the test is considered
# failed and the script moves on.
#
VM_TIMEOUT=600

# ============================================================
# REGIONS
# ============================================================
#
# Put regions you want to test first at the top.
#
# Based on your previous tests, we start with:
#
#   Spain Central
#   West Europe
#   UK South
#   South Africa North
#
# Then other regions.
#
# ============================================================

REGIONS=(
    "spaincentral"
    "westeurope"
    "uksouth"
    "southafricanorth"
    "northeurope"
    "eastus"
    "eastus2"
    "westus2"
    "centralus"
    "southcentralus"
    "australiaeast"
    "southeastasia"
    "canadacentral"
    "francecentral"
    "germanywestcentral"
    "swedencentral"
    "polandcentral"
)

# ============================================================
# VM SKUS
# ============================================================
#
# Test the smallest 1-vCPU SKUs first.
#
# If B-series fails due to capacity, try other 1-vCPU families.
#
# ============================================================

SKUS=(
    "Standard_B1s"
    "Standard_B1ms"
    "Standard_B1ls"
    "Standard_A1_v2"
    "Standard_F1s"
    "Standard_F1"
    "Standard_D1_v2"
    "Standard_DS1_v2"
)

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
# RESULT ARRAYS
# ============================================================

WORKING_REGIONS=()
WORKING_SKUS=()

FAILED_REGIONS=()
FAILED_SKUS=()
FAILED_REASONS=()

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

# ============================================================
# CHECK COMMAND
# ============================================================

command_exists() {

    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# CLEANUP
# ============================================================

cleanup_test_resource_group() {

    echo ""
    echo "Cleaning up temporary test resource group..."

    if az group exists \
        --name "$TEST_RESOURCE_GROUP" \
        2>/dev/null | grep -q "true"; then

        echo "Deleting:"
        echo "$TEST_RESOURCE_GROUP"

        az group delete \
            --name "$TEST_RESOURCE_GROUP" \
            --yes \
            --no-wait \
            >/dev/null 2>&1

        echo -e "${GREEN}Cleanup initiated.${NC}"

    else

        echo "Temporary resource group does not exist."

    fi
}

# ============================================================
# EXIT CLEANUP
# ============================================================

trap cleanup_test_resource_group EXIT

# ============================================================
# START
# ============================================================

clear 2>/dev/null || true

print_header "TechCrush RouteWell Real Azure VM Availability Tester"

echo ""
echo "This tool will find a REAL working combination of:"
echo ""
echo "  Azure Region"
echo "        +"
echo "  1-vCPU VM SKU"
echo ""
echo "RouteWell requires:"
echo ""
echo "  Web VM : 1 vCPU"
echo "  App VM : 1 vCPU"
echo "  DB VM  : 1 vCPU"
echo ""
echo "  Total : 3 vCPUs"
echo ""
echo "The tester will:"
echo ""
echo "  1. Check Azure CLI"
echo "  2. Check Azure login"
echo "  3. Check SSH key"
echo "  4. Create a temporary resource group"
echo "  5. Test one VM at a time"
echo "  6. Use a deployment timeout"
echo "  7. Delete successful test VMs"
echo "  8. Find the first working Region + SKU"
echo ""
echo "IMPORTANT:"
echo ""
echo "Your existing RouteWell resources will NOT be modified."
echo ""
echo "Temporary resource group:"
echo ""
echo "  $TEST_RESOURCE_GROUP"
echo ""

read -r -p "Continue? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then

    echo ""
    echo "Test cancelled."
    exit 0

fi

# ============================================================
# CHECK AZURE CLI
# ============================================================

print_section "Checking Azure CLI"

if ! command_exists az; then

    echo -e "${RED}ERROR: Azure CLI is not installed.${NC}"

    exit 1

fi

echo -e "${GREEN}Azure CLI found.${NC}"

# ============================================================
# CHECK AZURE LOGIN
# ============================================================

print_section "Checking Azure Login"

if ! az account show >/dev/null 2>&1; then

    echo -e "${RED}ERROR: You are not logged into Azure.${NC}"

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

    echo -e "${RED}ERROR: SSH public key not found.${NC}"

    echo ""
    echo "Expected:"
    echo "$SSH_PUBLIC_KEY"

    echo ""
    echo "Generate one with:"
    echo ""
    echo "  ssh-keygen -t ed25519"

    exit 1

fi

echo -e "${GREEN}SSH public key found:${NC}"

echo "$SSH_PUBLIC_KEY"

# ============================================================
# DISPLAY TEST CONFIGURATION
# ============================================================

print_header "RouteWell Real VM Testing Configuration"

echo ""
echo "Temporary Resource Group:"
echo "  $TEST_RESOURCE_GROUP"

echo ""
echo "VM Image:"
echo "  $VM_IMAGE"

echo ""
echo "VM Timeout:"
echo "  $VM_TIMEOUT seconds"

echo ""
echo "Candidate Regions:"

for REGION in "${REGIONS[@]}"; do

    echo "  - $REGION"

done

echo ""
echo "Candidate VM SKUs:"

for SKU in "${SKUS[@]}"; do

    echo "  - $SKU"

done

# ============================================================
# CREATE TEMPORARY RESOURCE GROUP
# ============================================================

print_section "Creating Temporary Test Resource Group"

if az group exists \
    --name "$TEST_RESOURCE_GROUP" \
    2>/dev/null | grep -q "true"; then

    echo "Temporary resource group already exists."

    echo ""
    echo "It will be reused for testing."

else

    echo "Creating temporary resource group..."

    if az group create \
        --name "$TEST_RESOURCE_GROUP" \
        --location "spaincentral" \
        --output none; then

        echo -e "${GREEN}Temporary resource group created.${NC}"

    else

        echo -e "${RED}Failed to create temporary resource group.${NC}"

        exit 1

    fi

fi

# ============================================================
# TEST REGION + SKU
# ============================================================

print_header "Starting Real Azure VM Tests"

REGION_COUNT=${#REGIONS[@]}

TOTAL_TESTS=$((REGION_COUNT * ${#SKUS[@]}))

CURRENT_TEST=0

FOUND_WORKING_COMBINATION="false"

for REGION in "${REGIONS[@]}"; do

    echo ""
    echo "============================================================"
    echo "Testing Region: $REGION"
    echo "============================================================"

    # ========================================================
    # CHECK REGION EXISTS
    # ========================================================

    echo ""
    echo "Checking region..."

    REGION_EXISTS=$(az account list-locations \
        --query "[?name=='$REGION'] | length(@)" \
        --output tsv \
        2>/dev/null)

    if [[ "$REGION_EXISTS" != "1" ]]; then

        echo -e "${YELLOW}Region is not recognized.${NC}"

        continue

    fi

    echo -e "${GREEN}Region recognized.${NC}"

    # ========================================================
    # TEST EACH SKU
    # ========================================================

    for SKU in "${SKUS[@]}"; do

        CURRENT_TEST=$((CURRENT_TEST + 1))

        VM_NAME="rwtest-${CURRENT_TEST}"

        echo ""
        echo "------------------------------------------------------------"

        echo "Test $CURRENT_TEST of $TOTAL_TESTS"

        echo "Region : $REGION"

        echo "SKU    : $SKU"

        echo "VM     : $VM_NAME"

        echo "------------------------------------------------------------"

        echo ""

        echo "Attempting real Azure VM deployment..."

        # ====================================================
        # RUN VM CREATE WITH TIMEOUT
        # ====================================================

        VM_OUTPUT_FILE=$(mktemp)

        timeout "$VM_TIMEOUT" az vm create \
            --resource-group "$TEST_RESOURCE_GROUP" \
            --name "$VM_NAME" \
            --location "$REGION" \
            --image "$VM_IMAGE" \
            --size "$SKU" \
            --admin-username "$ADMIN_USERNAME" \
            --ssh-key-values "$SSH_PUBLIC_KEY" \
            --authentication-type ssh \
            --public-ip-sku Standard \
            --output json \
            >"$VM_OUTPUT_FILE" 2>&1

        VM_EXIT_CODE=$?

        # ====================================================
        # SUCCESS
        # ====================================================

        if [[ "$VM_EXIT_CODE" -eq 0 ]]; then

            echo ""
            echo -e "${GREEN}============================================================${NC}"

            echo -e "${GREEN}SUCCESS! REAL VM DEPLOYMENT WORKED.${NC}"

            echo -e "${GREEN}============================================================${NC}"

            echo ""

            echo "Working Region : $REGION"

            echo "Working SKU    : $SKU"

            echo ""

            echo "Azure VM details:"
            echo ""

            cat "$VM_OUTPUT_FILE"

            echo ""

            WORKING_REGIONS+=("$REGION")

            WORKING_SKUS+=("$SKU")

            FOUND_WORKING_COMBINATION="true"

            rm -f "$VM_OUTPUT_FILE"

            echo ""
            echo "Deleting successful test VM..."

            az vm delete \
                --resource-group "$TEST_RESOURCE_GROUP" \
                --name "$VM_NAME" \
                --yes \
                --output none \
                2>/dev/null || true

            echo ""
            echo -e "${GREEN}Test VM deleted.${NC}"

            echo ""
            echo "A working Region + SKU combination has been found."

            echo ""
            echo "The script will stop testing."

            break 2

        fi

        # ====================================================
        # TIMEOUT
        # ====================================================

        if [[ "$VM_EXIT_CODE" -eq 124 ]]; then

            FAILURE_REASON="Deployment timed out after ${VM_TIMEOUT} seconds."

            echo ""
            echo -e "${YELLOW}TIMEOUT${NC}"

            echo "$FAILURE_REASON"

        else

            FAILURE_REASON=$(grep -E "SkuNotAvailable|RequestDisallowedByAzure|QuotaExceeded|AuthorizationFailed|InvalidTemplateDeployment" "$VM_OUTPUT_FILE" | head -1)

            if [[ -z "$FAILURE_REASON" ]]; then

                FAILURE_REASON="VM deployment failed."

            fi

            echo ""
            echo -e "${YELLOW}FAILED${NC}"

            echo "$FAILURE_REASON"

        fi

        FAILED_REGIONS+=("$REGION")

        FAILED_SKUS+=("$SKU")

        FAILED_REASONS+=("$FAILURE_REASON")

        echo ""

        echo "Moving to next SKU..."

        # ====================================================
        # CLEANUP FAILED VM RESOURCES
        # ====================================================

        echo ""

        echo "Cleaning failed test resources..."

        az vm delete \
            --resource-group "$TEST_RESOURCE_GROUP" \
            --name "$VM_NAME" \
            --yes \
            --output none \
            2>/dev/null || true

        az network public-ip delete \
            --resource-group "$TEST_RESOURCE_GROUP" \
            --name "${VM_NAME}PublicIP" \
            --output none \
            2>/dev/null || true

        az network nic delete \
            --resource-group "$TEST_RESOURCE_GROUP" \
            --name "${VM_NAME}VMNic" \
            --output none \
            2>/dev/null || true

        az network nsg delete \
            --resource-group "$TEST_RESOURCE_GROUP" \
            --name "${VM_NAME}NSG" \
            --output none \
            2>/dev/null || true

        az network vnet delete \
            --resource-group "$TEST_RESOURCE_GROUP" \
            --name "${VM_NAME}VNET" \
            --output none \
            2>/dev/null || true

        rm -f "$VM_OUTPUT_FILE"

    done

done

# ============================================================
# FINAL RESULTS
# ============================================================

print_header "RouteWell Real Azure VM Test Results"

echo ""

if [[ "$FOUND_WORKING_COMBINATION" == "true" ]]; then

    echo -e "${GREEN}SUCCESS!${NC}"

    echo ""

    echo "Azure successfully provisioned a test VM using:"

    echo ""

    echo "  Region : ${WORKING_REGIONS[0]}"

    echo "  SKU    : ${WORKING_SKUS[0]}"

    echo ""

    echo "Recommended RouteWell configuration:"
    echo ""

    echo "  LOCATION=\"${WORKING_REGIONS[0]}\""

    echo ""

    echo "  WEB_VM_SIZE=\"${WORKING_SKUS[0]}\""

    echo "  APP_VM_SIZE=\"${WORKING_SKUS[0]}\""

    echo "  DB_VM_SIZE=\"${WORKING_SKUS[0]}\""

    echo ""

    echo "IMPORTANT:"
    echo ""

    echo "The test only proves that Azure successfully created"
    echo "ONE VM using this Region + SKU combination."

    echo ""

    echo "Your RouteWell deployment requires 3 VMs."

    echo ""

    echo "Because your regional quota is currently 4 vCPUs,"
    echo "three 1-vCPU VMs should fit within the quota."

else

    echo -e "${RED}NO WORKING COMBINATION FOUND.${NC}"

    echo ""

    echo "Azure could not successfully provision a test VM"
    echo "using any tested Region + SKU combination."

    echo ""

    echo "This strongly suggests one of the following:"

    echo ""

    echo "  1. Subscription-level VM restrictions"

    echo "  2. Regional capacity restrictions"

    echo "  3. Location restrictions"

    echo "  4. VM family restrictions"

    echo "  5. Azure policy restrictions"

    echo "  6. Temporary Azure capacity limitations"

fi

# ============================================================
# FAILED TEST SUMMARY
# ============================================================

if [[ ${#FAILED_REGIONS[@]} -gt 0 ]]; then

    echo ""

    echo "Failed Test Summary"

    echo "------------------------------------------------------------"

    printf "%-25s %-25s %-50s\n" \
        "Region" \
        "SKU" \
        "Reason"

    echo "------------------------------------------------------------"

    for ((i=0; i<${#FAILED_REGIONS[@]}; i++)); do

        printf "%-25s %-25s %-50s\n" \
            "${FAILED_REGIONS[$i]}" \
            "${FAILED_SKUS[$i]}" \
            "${FAILED_REASONS[$i]}"

    done

fi

echo ""

echo "============================================================"

echo "RouteWell Azure VM Testing Complete"

echo "============================================================"

echo ""

# make it executable
# chmod +x scripts/find-routewell-vm.sh