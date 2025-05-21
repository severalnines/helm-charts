#!/bin/bash

echo "Helper script to create k8s secrets with s3 credentials" 
# Prompt for input
read -p "Enter S3_ENDPOINT: " s3_endpoint
read -p "Enter S3_ACCESSKEY: " s3_accesskey
read -sp "Enter S3_SECRETKEY: " s3_secretkey
echo
read -p "Enter S3_BUCKETNAME: " s3_bucketname

echo "Note! S3_INSECURE_SSL is normally 'false', but write 'true' if the access to s3 is not encrypted with TLS."
# Loop until user enters 'true' or 'false'
while true; do
    read -p "Enter S3_INSECURE_SSL (true/false): " s3_insecure_ssl
    if [[ "$s3_insecure_ssl" == "true" || "$s3_insecure_ssl" == "false" ]]; then
        break
    else
        echo "Please enter 'true' or 'false'."
    fi
done

# Base64 encode values
b64_endpoint=$(echo -n "$s3_endpoint" | base64)
b64_accesskey=$(echo -n "$s3_accesskey" | base64)
b64_secretkey=$(echo -n "$s3_secretkey" | base64)
b64_bucketname=$(echo -n "$s3_bucketname" | base64)
b64_insecure_ssl=$(echo -n "$s3_insecure_ssl" | base64)

# Write YAML to file
cat <<EOF > openstack-s3-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: openstack-s3
type: Opaque
data:
  MYCLOUD_S3_ENDPOINT: $b64_endpoint
  MYCLOUD_S3_ACCESSKEY: $b64_accesskey
  MYCLOUD_S3_SECRETKEY: $b64_secretkey
  MYCLOUD_S3_BUCKETNAME: $b64_bucketname
  MYCLOUD_S3_INSECURE_SSL: $b64_insecure_ssl
EOF

echo "Kubernetes Secret YAML created: openstack-s3-secrets.yaml"

