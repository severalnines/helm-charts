#!/bin/bash

set -e

echo "************************************************************************************************************"
echo "*                                                                                                          *"
echo "*                  Welcome to the CCX Installation and Configuration                                       *"
echo "*                                                                                                          *"
echo "*                                                                                                          *"
echo "************************************************************************************************************"

# Determine OS name
os=$(uname)

install_yq() {
    if ! command -v yq &> /dev/null; then
        echo "yq is not installed. Installing yq..."
        VERSION=v4.40.5

        # Set installation directory
        INSTALL_DIR="$HOME/.local/bin"
        mkdir -p "$INSTALL_DIR"

        if [ "$os" = "Linux" ]; then
            echo "This is a Linux machine."
            ARCH=$(uname -m)
            case $ARCH in
                x86_64)
                    BINARY=yq_linux_amd64
                    ;;
                aarch64 | arm64)
                    BINARY=yq_linux_arm64
                    ;;
                *)
                    echo "Unsupported architecture: $ARCH"
                    echo "Please install yq manually: https://github.com/mikefarah/yq#install"
                    exit 1
                    ;;
            esac
        elif [ "$os" = "Darwin" ]; then
            echo "This is a macOS machine."
            ARCH=$(uname -m)
            case $ARCH in
                x86_64)
                    BINARY=yq_darwin_amd64
                    ;;
                arm64)
                    BINARY=yq_darwin_arm64
                    ;;
                *)
                    echo "Unsupported architecture: $ARCH"
                    echo "Please install yq manually: https://github.com/mikefarah/yq#install"
                    exit 1
                    ;;
            esac
        else
            echo "Unsupported OS: $os"
            echo "Please install yq manually: https://github.com/mikefarah/yq#install"
            exit 1
        fi

        # Download yq
        echo "Downloading yq binary..."
        wget -q "https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}" -O "${INSTALL_DIR}/yq"
        if [ $? -ne 0 ]; then
            echo "Failed to download yq. Please check your internet connection and try again."
            exit 1
        fi

        # Make it executable
        chmod +x "${INSTALL_DIR}/yq"
        if [ $? -ne 0 ]; then
            echo "Failed to make yq executable. Please check your permissions."
            exit 1
        fi

        # Add INSTALL_DIR to PATH if not already present
        if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
            echo "Adding ${INSTALL_DIR} to PATH."
            export PATH="${INSTALL_DIR}:$PATH"
            # Optionally, add to shell profile for future sessions
            if [ -n "$BASH_VERSION" ]; then
                echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$HOME/.bashrc"
            elif [ -n "$ZSH_VERSION" ]; then
                echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$HOME/.zshrc"
            fi
        fi

        echo "yq installed successfully to ${INSTALL_DIR}."
    else
        echo "yq is already installed."
    fi
}

print_colored() {
    local COLOR_PREFIX="\033[0;"
    local GREEN="32m"
    local RED="31m"
    local YELLOW="33m"
    local INFO="96m"
    local NO_COLOR="\033[0m"
    local message="$1"
    local color="$2"
    local COLOR
    case "$color" in
        danger)
            COLOR="${COLOR_PREFIX}${RED}"
            ;;
        success)
            COLOR="${COLOR_PREFIX}${GREEN}"
            ;;
        debug)
            COLOR="${COLOR_PREFIX}${YELLOW}"
            ;;
        info)
            COLOR="${COLOR_PREFIX}${INFO}"
            ;;
        *)
            COLOR="${NO_COLOR}"
            ;;
    esac
    printf "${COLOR}%b${NO_COLOR}\n" "$message"
}

errorExit() {
    echo -e "\nERROR: $1\n"
    exit 1
}

readInputs() {
    local input
    while true; do
        read -r input
        if [ -z "$input" ]; then
            print_colored "Input cannot be empty." "danger"
            continue
        fi
        echo "$input"
        break
    done
}

check_tools_installed() {
    if ! command -v "$1" &> /dev/null; then
        errorExit "$1 is not installed. Please install $1 before running this script."
    fi
}

create_or_update_secret() {
    local secret_name="$1"
    shift
    local secret_args=("$@")
    if kubectl get secret "$secret_name" >/dev/null 2>&1; then
        kubectl create secret generic "$secret_name" "${secret_args[@]}" --dry-run=client -o yaml | kubectl apply -f -
        print_colored "Secret $secret_name updated successfully." "success"
    else
        kubectl create secret generic "$secret_name" "${secret_args[@]}"
        print_colored "Secret $secret_name created successfully." "success"
    fi
}

# Install yq
install_yq

# Ensure yq is available in the current shell session
export PATH="$HOME/.local/bin:$PATH"

# Check required tools
check_tools_installed "helm"
check_tools_installed "kubectl"

echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*                  Now we are going to configure the CCXDeps                                             *"
echo "*      This configuration is specific to the CCX Dependencies system for Quickstart Environments         *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"
echo ""
print_colored "Please ensure that your respective cloud provider command line tool is installed (e.g., aws-cli or openstack-cli)." "success"
print_colored "Please ensure that you're in the correct namespace when running this script." "success"

dependencies=()

print_colored "REQUIRED: Do you want to install the CCX Dependencies such as ingress, externaldns, db operators, etc.? [Y/n]" "success"
read -r installCCXDeps
installCCXDeps=${installCCXDeps:-Y}
case $installCCXDeps in
    [yY][eE][sS]|[yY])
        print_colored "REQUIRED: Do you want to install the ingress-nginx controller in k8s? (Defaults to No). [y/N]" "success"
        read -r ingressController
        ingressController=${ingressController:-N}
        if [[ "$ingressController" =~ ^[yY] ]]; then
            print_colored "Configuring Ingress controller..." "info"
            dependencies+=("--set ingressController.enabled=true")
        else
            print_colored "Skipping Ingress controller." "debug"
        fi

        print_colored "REQUIRED: Do you want to install External DNS in k8s to make services discoverable via public DNS servers? (Defaults to No). [y/N]" "success"
        read -r externalDns
        externalDns=${externalDns:-N}
        if [[ "$externalDns" =~ ^[yY] ]]; then
            print_colored "Configuring External DNS..." "info"
            print_colored "REQUIRED: Specify the domain filter to manage DNS records within a specific DNS zone (e.g., ccx.example.org):" "success"
            externalDnsDomainFilter=$(readInputs)
            dependencies+=("--set external-dns.enabled=true" "--set external-dns.domainFilters[0]=$externalDnsDomainFilter")
        else
            print_colored "Skipping External DNS." "debug"
        fi

        echo "Installing Helm CCXDeps..."
        helm repo add s9s https://severalnines.github.io/helm-charts/
        helm repo update
        helm upgrade --install ccxdeps s9s/ccxdeps --debug "${dependencies[@]}"
        if [ $? -eq 0 ]; then
            print_colored "Helm chart CCXDeps installed successfully." "success"
        else
            errorExit "Failed to install Helm chart CCXDeps."
        fi
        ;;
    [nN][oO]|[nN])
        print_colored "Skipping CCXDeps Installation." "debug"
        ;;
    *)
        print_colored "Invalid input." "danger"
        exit 1
        ;;
esac

print_colored "Please note that your values.yaml file will be rewritten if it already exists." "success"

# Prepare values.yaml
> "values.yaml"

configure_openstack() {
    print_colored "Configuring OpenStack..." "info"
    print_colored "REQUIRED: Vendor Name (e.g., your company name abbreviation):" "success"
    vendorName=$(readInputs)
    vendorName=${vendorName:-s9s}

    if ! command -v openstack &> /dev/null; then
        print_colored "OpenStack CLI is not installed. Please install it: https://docs.openstack.org/python-openstackclient/latest/" "danger"
        exit 1
    fi

    while true; do
        print_colored "Configuring OpenStack credentials as a secret..." "info"
        print_colored "REQUIRED: Enter OpenStack Project ID (OS_PROJECT_ID):" "success"
        OS_PROJECT_ID=$(readInputs)
        print_colored "REQUIRED: Enter OpenStack User Domain Name (OS_USER_DOMAIN_NAME):" "success"
        OS_USER_DOMAIN_NAME=$(readInputs)
        print_colored "REQUIRED: Enter OpenStack Username (OS_USERNAME):" "success"
        OS_USERNAME=$(readInputs)
        print_colored "REQUIRED: Enter OpenStack Password (OS_PASSWORD):" "success"
        OS_PASSWORD=$(readInputs)
        print_colored "REQUIRED: Enter OpenStack Auth URL (OS_AUTH_URL):" "success"
        OS_AUTH_URL=$(readInputs)

        # Display entered credentials (excluding password)
        echo ""
        print_colored "You have entered the following OpenStack credentials:" "info"
        echo "Vendor Name: $vendorName"
        echo "OS_PROJECT_ID: $OS_PROJECT_ID"
        echo "OS_USER_DOMAIN_NAME: $OS_USER_DOMAIN_NAME"
        echo "OS_USERNAME: $OS_USERNAME"
        echo "OS_AUTH_URL: $OS_AUTH_URL"
        echo ""

        # Verify OpenStack credentials
        print_colored "Verifying OpenStack credentials..." "info"
        export OS_PROJECT_ID OS_USER_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_AUTH_URL
        if openstack --os-auth-url "$OS_AUTH_URL" --os-project-id "$OS_PROJECT_ID" --os-username "$OS_USERNAME" --os-password "$OS_PASSWORD" token issue >/dev/null 2>&1; then
            print_colored "OpenStack authentication successful." "success"
            break
        else
            print_colored "OpenStack authentication failed. Please check your credentials." "danger"
            print_colored "Do you want to try again? [Y/n]" "info"
            read -r retry
            retry=${retry:-Y}
            if [[ ! "$retry" =~ ^[yY] ]]; then
                errorExit "Exiting due to failed OpenStack authentication."
            fi
        fi
    done

    # Create or update secret
    create_or_update_secret "openstack-creds" \
        --from-literal="${vendorName}_AUTH_URL=$OS_AUTH_URL" \
        --from-literal="${vendorName}_USERNAME=$OS_USERNAME" \
        --from-literal="${vendorName}_PASSWORD=$OS_PASSWORD" \
        --from-literal="${vendorName}_PROJECT_ID=$OS_PROJECT_ID" \
        --from-literal="${vendorName}_USER_DOMAIN_NAME=$OS_USER_DOMAIN_NAME"

    # Configure values.yaml using yq
    yq eval ".ccx.cloudSecrets[0] = \"openstack-creds\"" -i values.yaml
    yq eval ".ccx.services.deployer.config.openstack_vendors.$vendorName.auth_url = \"$OS_AUTH_URL\"" -i values.yaml
    yq eval ".ccx.services.deployer.config.openstack_vendors.$vendorName.project_id = \"$OS_PROJECT_ID\"" -i values.yaml

    # Additional OpenStack configurations can be added here
}

configure_aws() {
    print_colored "Configuring AWS..." "info"
    if ! command -v aws &> /dev/null; then
        print_colored "AWS CLI is not installed. Please install it: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" "danger"
        exit 1
    fi

    while true; do
        print_colored "Configuring AWS credentials as a secret..." "info"
        print_colored "REQUIRED: Enter your AWS Access Key ID:" "success"
        AWS_ACCESS_KEY_ID=$(readInputs)
        print_colored "REQUIRED: Enter your AWS Secret Access Key:" "success"
        AWS_SECRET_ACCESS_KEY=$(readInputs)

        # Display entered credentials (excluding secret key)
        echo ""
        print_colored "You have entered the following AWS credentials:" "info"
        echo "AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
        echo ""

        # Verify AWS credentials
        print_colored "Verifying AWS credentials..." "info"
        export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        if aws sts get-caller-identity >/dev/null 2>&1; then
            print_colored "AWS authentication successful." "success"
            break
        else
            print_colored "AWS authentication failed. Please check your credentials." "danger"
            print_colored "Do you want to try again? [Y/n]" "info"
            read -r retry
            retry=${retry:-Y}
            if [[ ! "$retry" =~ ^[yY] ]]; then
                errorExit "Exiting due to failed AWS authentication."
            fi
        fi
    done

    # Create or update secret
    create_or_update_secret "aws-secret" \
        --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"

    yq eval ".ccx.cloudSecrets[0] = \"aws-secret\"" -i values.yaml
    # Additional AWS configurations can be added here
}

# OpenStack configuration
echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*   Now we are going to configure the CCX OpenStack Configuration.                                       *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"

print_colored "Are you using OpenStack as your cloud provider vendor? [y/N] (default is No)" "success"
read -r openstackCloudVendor
openstackCloudVendor=${openstackCloudVendor:-N}
if [[ "$openstackCloudVendor" =~ ^[yY] ]]; then
    configure_openstack
else
    print_colored "Skipping OpenStack configuration." "debug"
fi

# AWS configuration
echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*   Now we are going to configure the CCX AWS Configuration.                                             *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"

print_colored "Do you want to use AWS as your cloud provider vendor? [y/N] (default is No)" "success"
read -r awsCloudVendor
awsCloudVendor=${awsCloudVendor:-N}
if [[ "$awsCloudVendor" =~ ^[yY] ]]; then
    configure_aws
else
    print_colored "Skipping AWS configuration." "debug"
fi

echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*                  Configuring CCX values file                                                           *"
echo "*      This section is for configuration specific to the CCX system                                      *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"

print_colored "REQUIRED: Input Session Domain URL (e.g., example.com):" "success"
sessionDomain=$(readInputs)
yq eval ".sessionDomain = \"$sessionDomain\"" -i values.yaml

print_colored "REQUIRED: Input ccxFQDN (e.g., ccx.example.com):" "success"
ccxFQDN=$(readInputs)
yq eval ".ccxFQDN = \"$ccxFQDN\"" -i values.yaml

print_colored "REQUIRED: Input ccFQDN (e.g., cc.example.com):" "success"
ccFQDN=$(readInputs)
yq eval ".ccFQDN = \"$ccFQDN\"" -i values.yaml

print_colored "REQUIRED: Input DNS names for users (e.g., ccx.example.com):" "success"
userDomain=$(readInputs)
yq eval ".ccx.userDomain = \"$userDomain\"" -i values.yaml

print_colored "[Optional]: Input storageClassName (default 'standard'):" "debug"
read -r storageClassName
storageClassName=${storageClassName:-standard}
yq eval ".storageClassName = \"$storageClassName\"" -i values.yaml

print_colored "[Optional]: Input SSL cluster Issuer:" "debug"
read -r sslIssuer
if [ -n "$sslIssuer" ]; then
    yq eval ".ccx.ingress.ssl.clusterIssuer = \"$sslIssuer\"" -i values.yaml
fi

echo "**********************************************************************************************************"
echo "*                                                                                                        *"
echo "*                  Now we are going to configure CMON                                                    *"
echo "*                                                                                                        *"
echo "**********************************************************************************************************"

print_colored "REQUIRED: Input your CMON Original license key here (press Ctrl+D to finish):" "success"
licenseKey=$(</dev/stdin)
encodedLicenseKey=$(echo "$licenseKey" | base64 | tr -d '\n')
yq eval ".cmon.license = \"$encodedLicenseKey\"" -i values.yaml

# Generate a random CMON password with letters and numbers
cmonPassword=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)
print_colored "Generated CMON password: $cmonPassword" "info"
yq eval ".cmon.password = \"$cmonPassword\"" -i values.yaml

print_colored "Your values.yaml has been generated. Use the following command to install CCX:" "success"
echo "helm upgrade --install ccx s9s/ccx --values values.yaml --debug"

