#!/bin/bash

set -e

read -p "Enter Resource Group Name: " RESOURCE_GROUP

echo "WARNING: This will delete:"
echo "Resource Group: $RESOURCE_GROUP"
echo "All RouteWell infrastructure inside it."

read -p "Type DELETE to continue: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo "Teardown cancelled."
    exit 0
fi

az group delete \
  --name "$RESOURCE_GROUP" \
  --yes \
  --no-wait

echo "Teardown initiated."