#!/bin/bash

echo "Helper script to create k8s secrets with s3 credentials" 

# Input validation loop
read_nonempty() {
  local varname="$1"
  local prompt="$2"
  local silent="$3"
  local value=""
  while true; do
    if [ "$silent" = "silent" ]; then
      read -sp "$prompt" value
      echo
    else
      read -p "$prompt" value
    fi
    if [ -n "$value" ]; then
      eval "$varname=\"\$value\""
      break
    else
      echo "Value cannot be empty. Please try again."
    fi
  done
}

read_nonempty s3_endpoint "Enter S3_ENDPOINT: "
read_nonempty s3_accesskey "Enter S3_ACCESSKEY: "
read_nonempty s3_secretkey "Enter S3_SECRETKEY: " silent
read_nonempty s3_bucketname "Enter S3_BUCKETNAME: "

echo "Note! S3_INSECURE_SSL is normally 'false', but write 'true' if the access to s3 is not encrypted with TLS."
while true; do
  read -p "Enter S3_INSECURE_SSL (true/false): " s3_insecure_ssl
  if [[ "$s3_insecure_ssl" == "true" || "$s3_insecure_ssl" == "false" ]]; then
    break
  else
    echo "Please enter 'true' or 'false'."
  fi
done

# Base64 encode values robustly (remove newlines)
b64() { echo -n "$1" | base64 | tr -d '\n'; }

b64_endpoint=$(b64 "$s3_endpoint")
b64_accesskey=$(b64 "$s3_accesskey")
b64_secretkey=$(b64 "$s3_secretkey")
b64_bucketname=$(b64 "$s3_bucketname")
b64_insecure_ssl=$(b64 "$s3_insecure_ssl")

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

chmod 600 openstack-s3-secrets.yaml

echo "Kubernetes Secret YAML created: openstack-s3-secrets.yaml"
