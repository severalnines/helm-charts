#!/bin/bash

echo "Creates a secrets.yaml file for your openstack credentials."
echo "" 

# Prompt for user input
read -p "Enter USERNAME: " username
read -sp "Enter PASSWORD: " password
echo
read -p "Enter USER_DOMAIN: " user_domain
read -p "Enter PROJECT_ID: " project_name
read -p "Enter AUTH_URL: " auth_url

# Base64 encode all values (no newline, handle UTF-8)
b64_username=$(echo -n "$username" | base64)
b64_password=$(echo -n "$password" | base64)
b64_project_name=$(echo -n "$project_name" | base64)
b64_auth_url=$(echo -n "$auth_url" | base64)
b64_user_domain=$(echo -n "$user_domain" | base64)

# Write YAML to file
cat <<EOF > openstack-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: openstack
type: Opaque
data:
  MYCLOUD_USERNAME: $b64_username
  MYCLOUD_PASSWORD: $b64_password
  MYCLOUD_PROJECT_ID: $b64_project_name
  MYCLOUD_AUTH_URL: $b64_auth_url
  MYCLOUD_USER_DOMAIN: $b64_user_domain
  MYCLOUD_USER_DOMAIN_NAME: $b64_user_domain
EOF

echo "Kubernetes Secret YAML created: openstack-secrets.yaml"

