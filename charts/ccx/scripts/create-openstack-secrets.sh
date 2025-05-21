#!/bin/bash

echo "Creates a secrets.yaml file for your openstack credentials."
echo ""

# Prompt for user input with validation
read -p "Enter USERNAME: " username
while [[ -z "$username" ]]; do
  echo "USERNAME cannot be empty."
  read -p "Enter USERNAME: " username
done

read -sp "Enter PASSWORD: " password
echo
while [[ -z "$password" ]]; do
  echo "PASSWORD cannot be empty."
  read -sp "Enter PASSWORD: " password
  echo
done

read -p "Enter USER_DOMAIN: " user_domain
while [[ -z "$user_domain" ]]; do
  echo "USER_DOMAIN cannot be empty."
  read -p "Enter USER_DOMAIN: " user_domain
done

read -p "Enter PROJECT_ID: " project_name
while [[ -z "$project_name" ]]; do
  echo "PROJECT_ID cannot be empty."
  read -p "Enter PROJECT_ID: " project_name
done

read -p "Enter AUTH_URL: " auth_url
while [[ -z "$auth_url" ]]; do
  echo "AUTH_URL cannot be empty."
  read -p "Enter AUTH_URL: " auth_url
done

# Base64 encode all values (no newline, handle UTF-8, compatible with macOS)
b64_username=$(echo -n "$username" | base64 | tr -d '\n')
b64_password=$(echo -n "$password" | base64 | tr -d '\n')
b64_project_name=$(echo -n "$project_name" | base64 | tr -d '\n')
b64_auth_url=$(echo -n "$auth_url" | base64 | tr -d '\n')
b64_user_domain=$(echo -n "$user_domain" | base64 | tr -d '\n')

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
