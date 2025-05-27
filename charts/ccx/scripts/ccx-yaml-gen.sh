#!/bin/bash

echo "************************************************************************************************************"
echo "*                                                                                                          *"
echo "*                  Welcome to the CCX Installation and Configuration                                       *"
echo "*                                                                                                          *"
echo "*                                                                                                          *"
echo "************************************************************************************************************"


# Determine OS name
os=$(uname)

# Ensure yq is installed
if ! command -v yq &> /dev/null; then
  if [ "$os" = "Linux" ]; then
    echo "This is a Linux Machine"
    BINARY=""
    VERSION=v4.40.5
    case $(uname -m) in
        x86_64) 
          BINARY=yq_linux_amd64
          wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/local/bin/yq >/dev/null 2>&1 &&\
          chmod +x /usr/local/bin/yq
          ;;
        arm)
          BINARY=yq_linux_arm64
          wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/local/bin/yq >/dev/null 2>&1 &&\
          chmod +x /usr/local/bin/yq
          ;;
        *) 
          echo "Unsupported arch for this installation of yq" 
          echo "Please install yq before running this script. see link https://mikefarah.gitbook.io/yq/v/v3.x"
          exit 1
          ;;
    esac

  elif [ "$os" = "Darwin" ]; then
    echo "This is an Apple Mac Machine"
    VERSION=v4.40.5
    case $(uname -m) in
        x86_64) 
          BINARY=yq_darwin_amd64
          wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/local/bin/yq >/dev/null 2>&1 &&\
          chmod +x /usr/local/bin/yq
          ;;
        arm64)
          BINARY=yq_darwin_arm64
          wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/local/bin/yq >/dev/null 2>&1 &&\
          chmod +x /usr/local/bin/yq
          ;;
        *) 
          echo "Unsupported arch for this installation of yq" 
          echo "Please install yq before running this script. see link https://mikefarah.gitbook.io/yq/v/v3.x"
          exit 1
          ;;
    esac
  else
    echo "Unsupported OS installation for yq installation"
    echo "Please install yq before running this script. see link https://mikefarah.gitbook.io/yq/v/v3.x"
    exit 1
  fi
fi

print_colored() {
    COLOR_PREFIX="\033[0;"
    GREEN="32m"
    RED="31m"
    YELLOW="33m"
    INFO="96m"
    NO_COLOR="\033[0m"
    if [ "$2" == "danger" ]; then
        COLOR="${COLOR_PREFIX}${RED}"
    elif [ "$2" == "success" ]; then
        COLOR="${COLOR_PREFIX}${GREEN}"
    elif [ "$2" == "debug" ]; then
        COLOR="${COLOR_PREFIX}${YELLOW}"
    elif [ "$2" == "info" ]; then
        COLOR="${COLOR_PREFIX}${INFO}"
    else
        COLOR="${NO_COLOR}"
    fi
    printf "${COLOR}%b${NO_COLOR}\n" "$1"
}

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}


function readInputs {
  while true; do
      read input
      if [ -z "$input" ]; then
        print_colored "Can't be empty" "danger"
        continue
      fi

      break
  done
} 


check_tools_installed() {
    if ! command -v $1 &> /dev/null; then
        errorExit "$1  is not installed. Please install $1  before running this script."
    fi
}

check_tools_installed "helm"
check_tools_installed "kubectl"

echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*                  Now we are going to configure the CCXDeps                                             *"
echo "*      This configuration is specific to the CCX Dependencies system for Quickstart Environments         *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"
echo ""
print_colored "Please ensure that your respective cloud provider command line tool is installed. Example aws-cli or openstack" "success"
print_colored "Please ensure that you're in correct namespace when running this script" "success"


generate_set_flags() {
    local dependencies=("$@")
    local set_flags=()
    dependencies=("$@")
    for dependency in "${dependencies[@]}"; do
        set_flags+=("$dependency")
    done
    echo "${set_flags[@]}"
}
print_colored "REQUIRED: Do you want to install the CCX Dependencies such as ingress, externaldns, db operators, etc?.[Y/n]" "success"
read installCCXDeps
case $installCCXDeps in
    [yY][eE][sS]|[yY])
    print_colored "REQUIRED: Do you want to install the ingress-nginx controller in k8s? (Defaults to false).[Y/n]" "success"
    read ingressController
    print_colored "REQUIRED: Do you want to install the External DNS in k8s that makes k8s services discoverable via public DNS servers? (Defaults to false).[Y/n]" "success"
    read externalDns
    case $ingressController in
        [yY][eE][sS]|[yY])
        echo "Configuring Ingress controller"
        dependencies+=("--set ingressController.enabled=true")
        set_flags=$(generate_set_flags "${dependencies[@]}")
        ;;
        [nN][oO]|[nN])
        print_colored "Skipping Ingress controller" "debug"
        ;;
        *)
        print_colored "Invalid input..." "danger"
        exit 1
        ;;
    esac
    case $externalDns in
        [yY][eE][sS]|[yY])
        echo "Configuring External DNS"
        print_colored "REQUIRED: Specify the domain filter to only manage DNS records within a specific DNS zone. eg. ccx.example.org" "success"
        read externalDnsDomainFilter
        if [[ -z "$externalDnsDomainFilter" ]]; then
            errorExit "Provide domain filter to manage DNS records if external-dns is enabled"
        else
            dependencies+=("--set external-dns.enabled=true --set \"external-dns.domainFilters[0]=$externalDnsDomainFilter\"")
            set_flags=$(generate_set_flags "${dependencies[@]}")
        fi
        ;;
        [nN][oO]|[nN])
        print_colored "Skipping External DNS" "debug"
        ;;
        *)
        print_colored "Invalid input..." "danger"
        exit 1
        ;;
    esac
    echo "Installing Helm CCXDeps..."
    helm repo add s9s https://severalnines.github.io/helm-charts/
    helm repo update
    helm upgrade --install ccxdeps s9s/ccxdeps --debug $set_flags
    if [ $? -eq 0 ]; then
        echo "Helm chart CCXDEPS installed successfully."
    else
        errorExit "Failed to install Helm chart CCXdeps."
    fi

    ;;
    [nN][oO]|[nN])
    print_colored "Skipping CCX deps Installation" "debug"
    ;;
    *)
    print_colored "Invalid input..." "danger"
    exit 1
    ;;
esac

print_colored "Please note that your values.yaml file will be rewritten incase if it exists already" "success"

if [ -f "values.yaml" ]; then
    >> "values.yaml"
else
    > "values.yaml"
fi

check_openstack_credentials() {
    if ! command -v openstack &> /dev/null
    then
        echo "See the installation instructions in the link https://docs.openstack.org/python-openstackclient/latest/"
        errorExit "openstack command line tool could not be found. Please install it before proceeding."
    fi
    echo "Configuring OpenStack credentials as secret..."
    print_colored "REQUIRED: Enter Openstack Project-level authentication scope by ID (OS_PROJECT_ID):" "success"
    read OS_PROJECT_ID
    # print_colored "REQUIRED: Enter Openstack Domain name containing project (OS_PROJECT_DOMAIN_NAME):" "success"
    # read OS_PROJECT_DOMAIN_NAME
    print_colored "REQUIRED: Enter Openstack Domain name containing user (OS_USER_DOMAIN_NAME):" "success"
    read OS_USER_DOMAIN_NAME
    print_colored "REQUIRED: Enter Openstack Authentication username (OS_USERNAME):" "success"
    read OS_USERNAME
    print_colored "REQUIRED: Enter Openstack Authentication password (OS_PASSWORD):" "success"
    read OS_PASSWORD
    print_colored "REQUIRED: Enter Openstack Authentication URL (OS_AUTH_URL):" "success"
    read OS_AUTH_URL
    export OS_USER_DOMAIN_NAME="$OS_USER_DOMAIN_NAME"
    export OS_PROJECT_ID="$OS_PROJECT_ID"
    export OS_USERNAME="$OS_USERNAME"
    export OS_PASSWORD="$OS_PASSWORD"
    export OS_AUTH_URL="$OS_AUTH_URL"
    openstack --os-auth-url "$OS_AUTH_URL" --os-project-id "$OS_PROJECT_ID" --os-username "$OS_USERNAME" --os-password "$OS_PASSWORD" --insecure token issue >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "OpenStack authentication successful."
        if kubectl get secret openstack-creds >/dev/null 2>&1; then
            kubectl create secret generic openstack-creds --from-literal="$vendorName"_AUTH_URL=$(echo "$OS_AUTH_URL") --from-literal="$vendorName"_USERNAME=$(echo "$OS_USERNAME") --from-literal="$vendorName"_PASSWORD=$(echo "$OS_PASSWORD") --from-literal="$vendorName"_PROJECT_ID=$(echo "$OS_PROJECT_ID") --from-literal="$vendorName"_USER_DOMAIN_NAME=$(echo "$OS_USER_DOMAIN_NAME") --dry-run=client -o yaml | kubectl apply -f -
            echo "Secret openstack-creds updated successfully."
        else
            kubectl create secret generic "openstack-creds" --from-literal="$vendorName"_AUTH_URL=$(echo "$OS_AUTH_URL") --from-literal="$vendorName"_USERNAME=$(echo "$OS_USERNAME") --from-literal="$vendorName"_PASSWORD=$(echo "$OS_PASSWORD") --from-literal="$vendorName"_PROJECT_ID=$(echo "$OS_PROJECT_ID") --from-literal="$vendorName"_USER_DOMAIN_NAME=$(echo "$OS_USER_DOMAIN_NAME") || errorExit "Error in creating openstack secret using kubectl"
            echo "Secret openstack-creds created successfully."
        fi
    else
        errorExit "OpenStack authentication failed. Please check your credentials."
    fi
}


check_aws_credentials() {
    if ! command -v aws &> /dev/null
    then
        echo "Please see this link https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        errorExit "aws-cli tool could not be found. Please install it before proceeding."
    fi
    print_colored "REQUIRED: Enter your AWS access key ID:" "success"
    read aws_access_key_id
    export AWS_ACCESS_KEY_ID="$aws_access_key_id"
    print_colored "REQUIRED: Enter your AWS secret access key:" "success"
    read aws_secret_access_key
    export AWS_SECRET_ACCESS_KEY="$aws_secret_access_key"
    echo "Checking AWS credentials..."
    aws sts get-caller-identity >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "AWS authentication successful."
        if kubectl get secret aws-secret >/dev/null 2>&1; then
            kubectl create secret generic aws-secret --from-literal=AWS_ACCESS_KEY_ID="$aws_access_key_id" --from-literal=AWS_SECRET_ACCESS_KEY="$aws_secret_access_key" --dry-run=client -o yaml | kubectl apply -f -
            echo "Secret aws-secret updated successfully."
        else
            kubectl create secret generic "aws-secret" --from-literal=AWS_ACCESS_KEY_ID="$aws_access_key_id" --from-literal=AWS_SECRET_ACCESS_KEY="$aws_secret_access_key" || errorExit "Error in creating aws secret using kubectl"
            echo "Secret aws-secret created successfully."
        fi
    else
        errorExit "AWS authentication failed. Please check your credentials."
    fi
}


echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*   Now we are going to configure the CCX Openstack Configuration.                                       *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"

# Openstack Cloud vendor
print_colored "Are you using Openstack as cloud provider vendor? [Y/n] (default is No) You can press \"Enter\" to skip it " "success"
read openstackCloudVendor
openstackCloudVendor=${openstackCloudVendor:-N}
case $openstackCloudVendor in
    [yY][eE][sS]|[yY])
    print_colored "REQUIRED: Vendor Name. eg, your company name as short" "success"
    read vendorName
    vendorName=${vendorName:-s9s}
    
    check_openstack_credentials

    check_tools_installed "openstack"

    yq eval ".ccx.cloudSecrets[0] = \"openstack-creds\"" -i values.yaml

    yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.auth_url= \"$OS_AUTH_URL\"" -i values.yaml

    print_colored "[optional]: Input openstack network api version. (default NetworkNeutron) You can press \"Enter\" to skip it" "debug"
    read networkApiVersion
    if [[ -z "$networkApiVersion" ]]; then
            echo "Using Default NetworkNeutron"
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.network_api_version = \"NetworkNeutron\"" -i values.yaml
    else
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.network_api_version = \"$networkApiVersion\"" -i values.yaml
    fi

    print_colored "[optional]: Input openstack compute api microversion. (default 2.79) You can press \"Enter\" to skip it" "debug"
    read computeApiVersion
    if [[ -z "$computeApiVersion" ]]; then
            echo "Using Default 2.79 version"
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.compute_api_microversion = \"2.79\"" -i values.yaml
    else
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.compute_api_microversion = \"$computeApiVersion\"" -i values.yaml
    fi

    print_colored "[optional]: Input openstack floating ip api microversion. (default FloatingIPV3) You can press \"Enter\" to skip it" "debug"
    read floatingApiVersion
    if [[ -z "$floatingApiVersion" ]]; then
            echo "Using Default FloatingIPV3 version"
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.floating_ip_api_version = \"FloatingIPV3\"" -i values.yaml
    else
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.floating_ip_api_version = \"$floatingApiVersion\"" -i values.yaml
    fi

    yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.project_id= \"$OS_PROJECT_ID\"" -i values.yaml

    print_colored "REQUIRED: Input openstack floating network id. The floating_network_id refers to a floating IP pool, which is a range of public IP addresses available for assignment to virtual machines." "success"
    read floatingNetworkId
    yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.floating_network_id= \"$floatingNetworkId\"" -i values.yaml

    print_colored "REQUIRED: Input openstack network id. The network id refers to the unique identifier assigned to a default network within the OpenStack environment" "success"
    read networkId
    yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.network_id= \"$networkId\"" -i values.yaml
    
    yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.max_jobs= 5" -i values.yaml
    yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.retries= 5" -i values.yaml

    print_colored "REQUIRED: openstack image id. we support ubuntu image 20 and 22.04 only. use openstack image list command to check id " "success"
    read openstackImageId
    print_colored "REQUIRED: openstack security group" "success"
    read openstackSecurityGroup
    openstackImageId=$openstackImageId openstackSecurityGroup=$openstackSecurityGroup yq eval '.ccx.services.deployer.config.openstack_vendors.s9s.regions.regionName |= . + { "image_id": env(openstackImageId), "secgrp_name": env(openstackSecurityGroup) }' -i values.yaml

    print_colored "[optional]: Input openstack s3 endpoint for backups. You can press \"Enter\" to skip it. backup will not be enabled" "debug"
    read openstackS3Endpoint
    if [[ -z "$openstackS3Endpoint" ]]; then
            echo  "Skipping backup"
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.s3.nothing_here = 0" -i values.yaml
    else
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.s3.endpoint = \"$openstackS3Endpoint\"" -i values.yaml

            print_colored "[Required:] Input your s3 Access Key" "success"
            read s3AccessKey
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.s3.access_key = \"$s3AccessKey\"" -i values.yaml

            print_colored "[Required:] Input your s3 secret Key" "success"
            read s3SecretKey
            yq eval ".ccx.services.deployer.config.openstack_vendors.s9s.s3.secret_key = \"$s3SecretKey\"" -i values.yaml

            print_colored "[Required:] Input your s3 Bucket name" "success"
            read s3BucketName
            if kubectl get secret openstack-s3  >/dev/null 2>&1; then
                kubectl create secret generic openstack-s3 --from-literal="$vendorName"_S3_ACCESSKEY=$(echo "$s3AccessKey") --from-literal="$vendorName"_S3_BUCKETNAME=$(echo "$s3BucketName") --from-literal="$vendorName"_S3_ENDPOINT=$(echo "$openstackS3Endpoint") --from-literal="$vendorName"_S3_SECRETKEY=$(echo "$s3SecretKey") --dry-run=client -o yaml | kubectl apply -f -
                echo "Secret openstack-s3 updated successfully."
            else
                kubectl create secret generic openstack-s3 --from-literal="$vendorName"_S3_ACCESSKEY=$(echo "$s3AccessKey") --from-literal="$vendorName"_S3_BUCKETNAME=$(echo "$s3BucketName") --from-literal="$vendorName"_S3_ENDPOINT=$(echo "$openstackS3Endpoint") --from-literal="$vendorName"_S3_SECRETKEY=$(echo "$s3SecretKey") || errorExit "Error in creating openstack-s3 secret using kubectl"
                echo "Secret openstack-s3 created successfully."
            fi
            yq eval ".ccx.cloudSecrets[1] = \"openstack-s3\"" -i values.yaml
    fi

    print_colored "REQUIRED: openstack region name" "success"
    read openstackRegion
    vendorName=$vendorName yq '(.ccx.services.deployer.config.openstack_vendors.s9s | key) = strenv(vendorName)' -i values.yaml
    vendorName=$vendorName yq '.ccx.config.clouds[0] = {"code": strenv(vendorName), "name": strenv(vendorName)}' -i values.yaml
    openstackRegion=$openstackRegion vendorName=$vendorName yq '(.ccx.services.deployer.config.openstack_vendors.[strenv(vendorName)].regions.regionName | key) = strenv(openstackRegion)' -i values.yaml
    openstackRegion=$openstackRegion yq '.ccx.config.clouds[0].regions[0] = {"code": strenv(openstackRegion), "display_code": strenv(openstackRegion),  "name": strenv(openstackRegion)}' -i values.yaml


    print_colored "REQUIRED: Two letter region country code. This is used for displaying the flag in ui of ccx application" "success"
    read openstackCountryCode
    openstackCountryCode=$openstackCountryCode yq '.ccx.config.clouds[0].regions[0] |= . + {"country_code": strenv(openstackCountryCode)}' -i values.yaml

    print_colored "REQUIRED: Two letter continent code. This is used for displaying the flag in ui of ccx application" "success"
    read openstackContinentCode
    openstackContinentCode=$openstackContinentCode yq '.ccx.config.clouds[0].regions[0] |= . + {"continent_code": strenv(openstackContinentCode)}' -i values.yaml

    print_colored "REQUIRED: Two letter region city. This is used for displaying the flag in ui of ccx application" "success"
    read openstackCityCode
    openstackCityCode=$openstackCityCode yq '.ccx.config.clouds[0].regions[0] |= . + {"city": strenv(openstackCityCode)}' -i values.yaml

    print_colored "REQUIRED: This must be a valid Openstack availability zone as defined by the cloud vendor. Enter comma-separated "sto1,sto2" or Q to quit:" "success"
    IFS=, read -ra openstackAZ
    iteration=0
    for az in "${openstackAZ[@]}"; do
      if [[ "$az" == "Q" ]]; then
        break 2
      fi
      az=$az iteration=$iteration yq 'with(.ccx.config.clouds[0].regions[0].availability_zones[env(iteration)]["code","name"]; . = strenv(az))' -i values.yaml
      ((iteration++))
    done

    yq '.ccx.config.clouds[0].network_types[0] = {"name": "Public", "code": "Public", "info": "All instances will be deployed with public IPs. Access to the public IPs is controlled by a firewall", "in_vpc": false }' -i values.yaml

    iteration=0
    while true; do
      print_colored 'REQUIRED: Input Instance type flavors name one by one that allow you to choose the size of your virtual machine. use "openstack flavor list" to see the flavor names. Example "v1-small" (or type 'Q' to exit) ' "success"
      read instanceType
      if [[ "$instanceType" == "Q" ]] || [[ "$instanceType" == "q" ]]; then
        break 2
      fi
      instanceType=$instanceType iteration=$iteration yq 'with(.ccx.config.clouds[0].instance_types[env(iteration)]["code","name","type"]; . = env(instanceType))' -i values.yaml
      print_colored "REQUIRED: Input CPU size of Instance. Enter CPU size in integers. Example "2":" "success"
      read instanceCPU
      instanceCPU=$instanceCPU iteration=$iteration yq 'with(.ccx.config.clouds[0].instance_types[env(iteration)]["cpu"]; . = env(instanceCPU))' -i values.yaml
      print_colored "REQUIRED: Input RAM size of Instance. Enter RAM size in integers. Example "4":" "success"
      read instanceRAM
      instanceRAM=$instanceRAM iteration=$iteration yq 'with(.ccx.config.clouds[0].instance_types[env(iteration)]["ram"]; . = env(instanceRAM))' -i values.yaml
      print_colored "REQUIRED: Input Disk size of Instance. Enter Disk size in integers. Example "60":" "success"
      read instanceDisk
      instanceDisk=$instanceDisk iteration=$iteration yq 'with(.ccx.config.clouds[0].instance_types[env(iteration)]["disk_size"]; . = env(instanceDisk))' -i values.yaml
      ((iteration++))
    done

    iteration=0
    while true; do
      print_colored 'REQUIRED: Input Volume type name one by one . use "openstack volume type list" to see the volume types name. Example "default" (or type 'Q' to exit) ' "success"
      read volumeType
      if [[ "$volumeType" == "Q" ]] || [[ "$volumeType" == "q" ]]; then
        break 2
      fi
      volumeType=$volumeType iteration=$iteration yq 'with(.ccx.config.clouds[0].volume_types[env(iteration)]["code","name"]; . = strenv(volumeType))' -i values.yaml
      iteration=$iteration yq 'with(.ccx.config.clouds[0].volume_types[env(iteration)]["info"]; . = "Storage is directly attached to the server")' -i values.yaml
      iteration=$iteration yq 'with(.ccx.config.clouds[0].volume_types[env(iteration)]["has_iops"]; . = false)' -i values.yaml
      iteration=$iteration yq '.ccx.config.clouds[0].volume_types[env(iteration)].size |= . + { "min": 80, "max": 8000, "default": 80 }' -i values.yaml
      ((iteration++))
    done
    ;;
    [nN][oO]|[nN])
    print_colored "Skipping Openstack Config" "debug"
    ;;
    *)
    print_colored "Invalid input..." "danger"
    exit 1
    ;;
esac



echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*   Now we are going to configure the CCX AWS Configuration.                                             *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"

# Aws Cloud vendor
print_colored "Are you using AWS as cloud provider vendor? [Y/n] (default is No) You can press \"Enter\" to skip it " "success"
read awsCloudVendor
awsCloudVendor=${awsCloudVendor:-N}
case $awsCloudVendor in
    [yY][eE][sS]|[yY])
    check_aws_credentials
    yq eval ".ccx.cloudSecrets[0] = \"aws-secret\"" -i values.yaml
    ;;
    [nN][oO]|[nN])
    print_colored "Skipping Aws config" "debug"
    ;;
    *)
    print_colored "Invalid input..." "danger"
    exit 1
    ;;
esac


echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*   Now we are going to configure the CCX VMWARE Configuration.                                             *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"


# Vmware Cloud vendor
print_colored "Are you using Vmware as cloud provider vendor? [Y/n] (default is No) You can press \"Enter\" to skip it " "success"
read vmwareCloudVendor
vmwareCloudVendor=${vmwareCloudVendor:-N}
case $vmwareCloudVendor in
    [yY][eE][sS]|[yY])
    print_colored "REQUIRED: Input the ESXi URL address. Example \"https://140.90.180.200/sdk\" " "success"
    readInputs
    yq eval ".ccx.services.deployer.config.vmware_vendors.vmware.vc_url = \"$input\"" -i values.yaml

    print_colored "REQUIRED: Input the name of the data center. Example \"ha-datacenter\" " "success"
    readInputs
    yq eval ".ccx.services.deployer.config.vmware_vendors.vmware.dc = \"$input\"" -i values.yaml

    print_colored "REQUIRED: Input the path to the Ubuntu ISO image with the information in which datastore the ISO is stored. Example \"[datastore1] iso/ccx.iso\" " "success"
    readInputs
    yq eval ".ccx.services.deployer.config.vmware_vendors.vmware.iso = \"$input\"" -i values.yaml

    print_colored "REQUIRED: Input the network to which the new VMs will be attached. Example \"public.4\" " "success"
    readInputs
    yq eval ".ccx.services.deployer.config.vmware_vendors.vmware.network = \"$input\"" -i values.yaml

    print_colored "REQUIRED: Input the network adapter type . Example \"vmxnet3\" " "success"
    readInputs
    yq eval ".ccx.services.deployer.config.vmware_vendors.vmware.network_adapter = \"$input\"" -i values.yaml

    print_colored "REQUIRED: Input the resource pool name . Example \"esxi./Resources\" " "success"
    readInputs
    yq eval ".ccx.services.deployer.config.vmware_vendors.vmware.resource_pool = \"$input\"" -i values.yaml

    print_colored "REQUIRED: Input the ESXi username. Example \"root\" " "success"
    readInputs
    yq eval ".ccx.services.deployer.config.vmware_vendors.vmware.vc_username = \"$input\"" -i values.yaml

    print_colored "REQUIRED: Input the name of the datastore . Example \"datastore1\" " "success"
    readInputs
    yq eval ".ccx.services.deployer.config.vmware_vendors.vmware.vm_path = \"$input\"" -i values.yaml

    print_colored "REQUIRED: Vendor Name. eg, your company name as short. example \"vmware\" " "success"
    read vendorName
    print_colored "REQUIRED: vmware region name" "success"
    read vmwareRegion
    vendorName=${vendorName:-vmware}
    vendorName=$vendorName yq '(.ccx.services.deployer.config.vmware_vendors.vmware | key) = strenv(vendorName)' -i values.yaml
    vendorName=$vendorName yq '.ccx.config.clouds[0] = {"code": strenv(vendorName), "name": strenv(vendorName)}' -i values.yaml
    vmwareRegion=$vmwareRegion yq '.ccx.config.clouds[0].regions[0] = {"code": strenv(vmwareRegion), "display_code": strenv(vmwareRegion),  "name": strenv(vmwareRegion)}' -i values.yaml


    print_colored "REQUIRED: Two letter region country code. This is used for displaying the flag in ui of ccx application" "success"
    read vmwareCountryCode
    vmwareCountryCode=$vmwareCountryCode yq '.ccx.config.clouds[0].regions[0] |= . + {"country_code": strenv(vmwareCountryCode)}' -i values.yaml

    print_colored "REQUIRED: Two letter continent code. This is used for displaying the flag in ui of ccx application" "success"
    read vmwareContinentCode
    vmwareContinentCode=$vmwareContinentCode yq '.ccx.config.clouds[0].regions[0] |= . + {"continent_code": strenv(vmwareContinentCode)}' -i values.yaml

    print_colored "REQUIRED: Two letter region city. This is used for displaying the flag in ui of ccx application" "success"
    read vmwareCityCode
    vmwareCityCode=$vmwareCityCode yq '.ccx.config.clouds[0].regions[0] |= . + {"city": strenv(vmwareCityCode)}' -i values.yaml

    print_colored "REQUIRED: This must be a valid Openstack availability zone as defined by the cloud vendor. Enter comma-separated "default" or Q to quit:" "success"
    IFS=, read -ra vmwareAZ
    iteration=0
    for az in "${vmwareAZ[@]}"; do
      if [[ "$az" == "Q" ]]; then
        break 2
      fi
      az=$az iteration=$iteration yq 'with(.ccx.config.clouds[0].regions[0].availability_zones[env(iteration)]["code","name"]; . = strenv(az))' -i values.yaml
      ((iteration++))
    done

    yq '.ccx.config.clouds[0].network_types[0] = {"name": "Public", "code": "Public", "info": "All instances will be deployed with public IPs. Access to the public IPs is controlled by a firewall", "in_vpc": false }' -i values.yaml

    iteration=0
    while true; do
      print_colored 'REQUIRED: Input Instance type flavors name one by one that allow you to choose the size of your virtual machine. use "vmware flavor list" to see the flavor names. Example "v1-small" (or type 'Q' to exit) ' "success"
      read instanceType
      if [[ "$instanceType" == "Q" ]] || [[ "$instanceType" == "q" ]]; then
        break 2
      fi
      instanceType=$instanceType iteration=$iteration yq 'with(.ccx.config.clouds[0].instance_types[env(iteration)]["code","name","type"]; . = env(instanceType))' -i values.yaml
      print_colored "REQUIRED: Input CPU size of Instance. Enter CPU size in integers. Example "2":" "success"
      read instanceCPU
      instanceCPU=$instanceCPU iteration=$iteration yq 'with(.ccx.config.clouds[0].instance_types[env(iteration)]["cpu"]; . = env(instanceCPU))' -i values.yaml
      print_colored "REQUIRED: Input RAM size of Instance. Enter RAM size in integers. Example "4":" "success"
      read instanceRAM
      instanceRAM=$instanceRAM iteration=$iteration yq 'with(.ccx.config.clouds[0].instance_types[env(iteration)]["ram"]; . = env(instanceRAM))' -i values.yaml
      print_colored "REQUIRED: Input Disk size of Instance. Enter Disk size in integers. Example "60":" "success"
      read instanceDisk
      instanceDisk=$instanceDisk iteration=$iteration yq 'with(.ccx.config.clouds[0].instance_types[env(iteration)]["disk_size"]; . = env(instanceDisk))' -i values.yaml
      ((iteration++)) 
    done

    iteration=0
    while true; do
      print_colored 'REQUIRED: Input Volume type name one by one . use "vmware volume type list" to see the volume types name. Example "scsi" (or type 'Q' to exit) ' "success"
      read volumeType
      if [[ "$volumeType" == "Q" ]] || [[ "$volumeType" == "q" ]]; then
        break 2
      fi
      volumeType=$volumeType iteration=$iteration yq 'with(.ccx.config.clouds[0].volume_types[env(iteration)]["code","name"]; . = strenv(volumeType))' -i values.yaml
      iteration=$iteration yq 'with(.ccx.config.clouds[0].volume_types[env(iteration)]["info"]; . = "Storage is directly attached to the server")' -i values.yaml
      iteration=$iteration yq 'with(.ccx.config.clouds[0].volume_types[env(iteration)]["has_iops"]; . = false)' -i values.yaml
      iteration=$iteration yq '.ccx.config.clouds[0].volume_types[env(iteration)].size |= . + { "min": 80, "max": 8000, "default": 80 }' -i values.yaml
      ((iteration++))
    done

    print_colored "[Required:] Input your ESX PASSWORD .To set up the password for user *vm_username* we need to create a Kubernetes secret" "success"
    read esxPassword
    if kubectl get secret "$vendorName" >/dev/null 2>&1; then
        kubectl create secret generic "$vendorName" --from-literal="$vendorName"_ESX_PASSWORD="$esxPassword" --dry-run=client -o yaml | kubectl apply -f -
        echo "Secret "$vendorName" updated successfully."
    else
        kubectl create secret generic "$vendorName" --from-literal="$vendorName"_ESX_PASSWORD="$esxPassword"  || errorExit "Error in creating vmware secret using kubectl"
        echo "Secret "$vendorName" created successfully."
    fi
    yq eval ".ccx.cloudSecrets[0] = \"$vendorName\"" -i values.yaml
    ;;
    [nN][oO]|[nN])
    print_colored "Skipping vmware config" "debug"
    ;;
    *)
    print_colored "Invalid input..." "danger"
    exit 1
    ;;
esac

echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*                  Configuration CCX values file                                                         *"
echo "*      This section is for configuration specific to the CCX system                                      *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"

print_colored "REQUIRED: Input Session Domain URL: This is used across the app to identify your instance. for example example.com" "success"
readInputs
yq eval ".sessionDomain = \"$input\"" -i values.yaml

print_colored "REQUIRED: Input ccxFQDN: fqdn of this ccx instance, for example ccx.example.com" "success"
readInputs
ccxFQDN=$input
yq eval ".ccxFQDN = \"$ccxFQDN\"" -i values.yaml

print_colored "REQUIRED: Input ccFQDN: fqdn of this ccx instance, for example cc.example.com" "success"
readInputs
yq eval ".ccFQDN = \"$input\"" -i values.yaml

print_colored "REQUIRED: Input DNS names to users. this should be a domain you can configure into externaldns. for example ccx.example.com" "success"
readInputs
yq eval ".ccx.userDomain= \"$input\"" -i values.yaml

print_colored "[optional]: Input storageClassName: k8s storage class used for PVs across CCX. This is a global variable applied to all PVCs/PVs. (default standard). You can press \"Enter\" to skip it" "debug"
read storageClassName
if [[ -z "$storageClassName" ]]; then
        echo "Using Default storageclass"
else
        yq eval ".storageClassName = \"$storageClassName\"" -i values.yaml
fi

print_colored "[optional]: Input SSL cluster Issuer. You can press \"Enter\" to skip it" "debug"
read sslIssuer
if [[ -z "$sslIssuer" ]]; then
        echo "Using Default "
else
        yq eval ".ccx.ingress.ssl.clusterIssuer= \"$sslIssuer\"" -i values.yaml
fi

echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*   Now we are going to configure the CMON                                                               *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"

# CMON DB configs
print_colored "REQUIRED: Input your CMON Original license key here by copy pasting without base64 encoding. (press Ctrl+D to finish after pasting the license)" "success"
encode_base64() {
    base64 <<< "$1" | tr -d '\n'
}
base64_input=""
while IFS= read -r line; do
    base64_input+="$line"
done
encoded_content=$(encode_base64 "$base64_input")
yq eval ".cmon.license = \"$encoded_content\"" -i values.yaml


print_colored "REQUIRED: Input CMON password. valid values example \"8fcf2304e46f39fa70710583a41455fd39cc5408\" " "success"
readInputs
yq eval ".cmon.password = \"$input\"" -i values.yaml

echo "You will have your values.yaml generated in your path. use 'helm upgrade --install ccx s9s/ccx --values values.yaml --debug' to install ccx"
