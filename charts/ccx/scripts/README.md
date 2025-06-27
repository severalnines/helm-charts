
# CCX Logging Utility - gather-logs.sh

This script is designed to facilitate the collection of logs and operational data from a CCX services and components within a Kubernetes environment. It specifically targets a suite of services CCX services along with cmon services, gathering their logs, s9s cluster and job information, and packaging them into a compressed archive for analysis.

## Prerequisites

- **Kubernetes Environment**: Ensure the script is executed within the correct Kubernetes cluster and namespace context.
- **kubectl**: The Kubernetes command-line tool, `kubectl`, must be installed and configured to communicate with your cluster.
- **Permissions**: Adequate permissions are required to fetch logs and execute commands within pods.

## Usage

1. Ensure you have the necessary permissions and are in the correct Kubernetes namespace.
2. Run the script:

   ```bash
   ./gather-logs.sh
   ```
   
   Optionally, provide parameters:
   
   ```bash
    Usage: ./gather-logs.sh [-n namespace] [-o output] [-h]
    -n namespace: Namespace to gather logs from. Default is current namespace.
    -o output: Output .tar.gz  file name. Default is ccx-logs.tar.gz.
    -h: Display this help.
    All parameters are optional.
   ```

3. Upon completion, the script will output the location of the `ccx-logs.tar.gz` file containing the collected logs.

## Functionality

1. **Initial Check**: Verifies the presence of the `cmon-master-0` pod to ensure the script is executed in the correct environment.
2. **Log Collection**: Iterates through the list of services, gathering logs from all containers within pods labeled with the service name.
3. **s9s Info**: Gathers cluster and job information using the `s9s` tool from the `cmon-master-0` pod.
4. **Failed Job Logs**: Collects logs for the last 10 failed jobs, if any.
5. **Partial CCX database dump**: Dumps some database tables for review. Sensitive or user data is not dumped!
6. **Archiving**: Packages all collected data into a compressed file named `ccx-logs.tar.gz`.
7. **Cleanup**: Removes the temporary directory used for log collection.

## Troubleshooting

If you encounter an error stating `cmon-master-0 pod not found`, verify that:
- You are in the correct Kubernetes cluster and namespace.
- Your `kubectl` is properly configured and has the necessary permissions.

## Note

This script is intended for use by system administrators and support personnel familiar with Kubernetes. Use with caution and ensure you have the appropriate authorizations before accessing and collecting data from production environments.


# CCX Easy Install and values file generation script

This script is designed to facilitate easy installation of CCX deps and generate values within a Kubernetes environment.

## Prerequisites

- **Kubernetes Environment**: Ensure the script is executed within the correct Kubernetes cluster and namespace context.

  `kubectl config set-context --current --namespace=your-namespace`
- **Tool**: `kubectl`, `helm`,  must be installed and configured to communicate with your cluster.
  * [kubectl installation](https://kubernetes.io/docs/tasks/tools/#kubectl)
  * [helm installation](https://helm.sh/docs/intro/install/)
- **Permissions**: Admin permissions are required within namespace execute commands and install operators.

## Usage

1. Ensure you have the necessary permissions and are in the correct Kubernetes namespace.
2. Run the script:

   ```bash
   ./ccx-yaml-gen.sh
   ```

## Note

This script is intended for use by system administrators and support personnel familiar with Kubernetes. Use with caution and ensure you have the appropriate authorizations with production environments.


