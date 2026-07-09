# Local Agent Installation for SAS 360 Marketing AI in SAS Customer Intelligence 360

On this page:

* [Overview](#overview)
* [Set Up the Helm Repository](#set-up-the-helm-repository)
* [Download the Release Archive](#download-the-release-archive)
* [Prerequisites](#prerequisites)
* [Deploy the Local Agent](#deploy-the-local-agent)
* [Backup and Restore](#backup-and-restore)
* [Database Maintenance for the Local Agent](#database-maintenance-for-the-local-agent)
* [Contributing](#contributing)
* [License](#license)
* [Additional Resources](#additional-resources)

## Overview

Use SAS 360 Marketing AI to accelerate your use of analytics. Offload the routine analysis problems that you face
so that you can free up time and resources to focus on more difficult analytical challenges. SAS 360 Marketing AI
can guide you through the steps to set up analytics and modeling for common marketing scenarios without the
expectation that you have access to a data scientist.

The local agent enables you to run these processes where your data is stored so that you do not have to upload
your data to the cloud. The local agent creates a secure socket connection between your environment and SAS
Customer Intelligence 360. The actions that you take in the user interface for SAS Customer Intelligence 360
are then communicated to your environment, where the actual modeling and analytics are run.

After the analysis is complete, only the results are sent back to SAS Customer Intelligence 360. This keeps your
data in your chosen environments while allowing you to take full advantage of the features of SAS Customer
Intelligence 360.

**Note:** Some links in the document go to outside pages. Open these links in a new tab to keep this README open in the existing tab.

<!-- ### What's New
If applicable to your project, list new features you want users to be aware of.
This section might supplement the Changelog file from the repository and only highlight important changes.
-->

## Set Up the Helm Repository
   
 1. Make sure that you are using Bash as the shell environment.
   * AWS CloudShell uses Bash by default.
   * In Azure Cloud Shell, select Bash as the default shell.
  
2. Check the Helm version:
      ```sh
      helm version --short
      ```
      
   **Important:** Helm v3.18.XX or v3.19.XX is required for this deployment. Verify that the output starts with v3.18. or v3.19. (for example, v3.18.1+gXXXXXXX).
   
3. If Helm is not installed, use the following commands to install the correct version
   
      ```sh
      curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
      ```
      
      ```sh
      chmod 700 get_helm.sh
      ```
      
      ```sh
      DESIRED_VERSION=v3.18.1 ./get_helm.sh
      ```
4. If Helm is installed and the version is not at version 3.18 or 3.19, use the following command to install and update Helm to the correct version:
   
      ```sh
      mkdir -p $HOME/.local/bin && \
      export PATH="$HOME/.local/bin:$PATH" && \
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && \
      wget https://get.helm.sh/helm-v3.18.0-linux-amd64.tar.gz && \
      tar -zxvf helm-v3.18.0-linux-amd64.tar.gz && \
      mv linux-amd64/helm $HOME/.local/bin/helm && \
      rm -rf linux-amd64 helm-v3.18.0-linux-amd64.tar.gz
      ```
   
      ```sh
      #Clear terminal cache
      hash -r
      ```
   
      ```sh
      #Check helm version
      helm version
      ```

 5. Get the public helm repo and check the available versions:

    ```sh
    # Add the repo
    helm repo add ci360-helm-charts https://sassoftware.github.io/ci360-helm-charts/packages
    ```

    ```sh
    # Update the repo
    helm repo update
    ```

    ```sh
    # Verify that the 'sas-marketing-ai' chart is available
    helm search repo ci360-helm-charts/sas-marketing-ai
    ```
    
    **Important**: Make note of the chart version for later steps in the deployment.

    Optionally, you can inspect the chart contents by running these commands:

    ```sh
    # Show the README for a specific chart version
    helm show readme ci360-helm-charts/sas-marketing-ai --version <CHART VERSION from the helm search>
    ```

    ```sh
    # Show the default values for a specific chart version
    helm show values ci360-helm-charts/sas-marketing-ai --version <CHART VERSION from the helm search>
    ```

    ```sh  
    # Show the chart metadata for a specific chart version
    helm show chart ci360-helm-charts/sas-marketing-ai --version <CHART VERSION from the helm search>
    ```
  
## Download the Release Archive

The deployment scripts are provided in a release archive that corresponds to your deployment chart version. Download and extract this archive once, then use it for all subsequent steps.

1. Download and extract the release archive:

   ```sh
   curl -L -o ci360-helm-charts-tools-marketing-ai-<CHART_VERSION>.tar.gz \
     https://github.com/sassoftware/ci360-helm-charts/archive/refs/tags/tools-marketing-ai-<CHART_VERSION>.tar.gz
   ```

   ```sh
   tar -xzf ci360-helm-charts-tools-marketing-ai-<CHART_VERSION>.tar.gz
   ```

   > **Note:** Replace `<CHART_VERSION>` with the version of the chart you plan to deploy (e.g., `0.39.7`). For example:
   > ```sh
   > curl -L -o ci360-helm-charts-tools-marketing-ai-0.39.7.tar.gz \
   >   https://github.com/sassoftware/ci360-helm-charts/archive/refs/tags/tools-marketing-ai-0.39.7.tar.gz
   > tar -xzf ci360-helm-charts-tools-marketing-ai-0.39.7.tar.gz
   > ```

2. Navigate to the tools/marketing-ai directory:

   ```sh
   cd ci360-helm-charts-tools-marketing-ai-<CHART_VERSION>/tools/marketing-ai
   ```

   All deployment scripts in the following steps are run from this directory.

## Prerequisites

Before you begin to set up the local agent, make sure that you have completed these prerequisites.

### Request a License

Contact your SAS representative and request a license for Marketing AI for SAS Customer
Intelligence 360. SAS will add this license to your existing tenant and send a welcome email
that includes a link to this repository.

### Establish an Account with a Cloud-Service Provider

Set up an account with a cloud-service provider, such as Amazon Web Services (AWS) or Microsoft Azure.
<!-- or Google Cloud Platform (GCP). -->

### Deploy a Kubernetes Cluster

Deploy and configure a Kubernetes cluster. The cluster must be configured to connect to your
cloud-service provider. For more information, see
<a href="https://kubernetes.io/docs/setup/" target="_blank">https://kubernetes.io/docs/setup/</a>.

For detailed cluster requirements, node configuration, IAM permissions, and storage class prerequisites specific to your cloud provider, see the documentation files in the release archive you downloaded (see [Download the Release Archive](#download-the-release-archive)):

- `README-aws-infrastructure.md`
- `README-azure-infrastructure.md`

### Collect the Required Deployment Information
Gather the deployment-specific configuration values that are listed in the following table for your cloud provider. Some values are obtained from your cloud environment, while others are provided by SAS. You will use these values later to populate the local agent YAML configuration file.

<table role="table" style="width: 100%;">
     <colgroup>
       <col span="1" style="width: 10%;">
       <col span="1" style="width: 20%;">
       <col span="1" style="width: 20%;">
       <col span="1" style="width: 50%;">
     </colgroup>
 <thead style="background-color: #0766d1; font-weight: bold;">
  <tr>
   <th>Parameter</th>
   <th>Required?</th>
   <th>AWS Value</th>
   <th>Azure Value</th>
   <th>Comments</th>
  </tr>
 </thead>
 <tr>
  <td>
  <p>_agentpool</p>
  </td>
  <td>
  <p>Azure only</p>
  </td>
  <td>
  <p>N/A</p>
  </td>
  <td>
  <p>Node pool name (for example,
  agentpool)</p>
  </td>
  <td>
  <p>In AKS, navigate to <b>Settings</b>
  &gt; <b>Node Pools</b>.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_storageAccountName</p>
  </td>
  <td>
  <p>Azure only</p>
  </td>
  <td>
  <p>N/A</p>
  </td>
  <td>
  <p>Azure Storage Account name</p>
  </td>
  <td>
  <p>Name of the Azure Storage
  Account that is used by the deployment.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_storageAccountResourceId</p>
  </td>
  <td>
  <p>Azure only</p>
  </td>
  <td>
  <p>N/A</p>
  </td>
  <td>
  <p>Azure Storage Account resource ID</p>
  </td>
  <td>
  <p>Full Azure resource ID of the storage
  account. This value is used by lifecycle policy management to resolve the
  subscription ID, resource group, and storage account name.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_dagsStorageClassName</p>
  </td>
  <td>
  <p>Yes</p>
  </td>
  <td>
  <p>efs-sc</p>
  </td>
  <td>
  <p>azurefile-csi</p>
  </td>
  <td>
  <p>Storage class that is used to
  share DAGs across pods.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_externalGatewayHost</p>
  </td>
  <td>
  <p>Yes</p>
  </td>
  <td>
  <p>Customer-specific value</p>
  </td>
  <td>
  <p>Customer-specific value</p>
  </td>
  <td>
  <p>In SAS Customer Intelligence
  360, navigate to <b>General Settings</b> &gt; <b>Access Points</b>.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_k8sAuthSecretName</p>
  </td>
  <td>
  <p>Yes</p>
  </td>
  <td>
  <p>Kubernetes secret name</p>
  </td>
  <td>
  <p>Kubernetes secret name</p>
  </td>
  <td>
  <p>Value must match the secret and
  namespace that were created during configuration of the Kubernetes
  environment.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_remoteBaseLogFolder</p>
  </td>
  <td>
  <p>Yes</p>
  </td>
  <td>
  <p>s3:///mai/logs/local-agent</p>
  </td>
  <td>
  <p>wasb://airflow-logs@.blob.core.windows.net/logs</p>
  </td>
  <td>
  <p>Location used for Airflow log
  storage.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_s3BucketName</p>
  </td>
  <td>
  <p>AWS only</p>
  </td>
  <td>
  <p>S3 bucket name</p>
  </td>
  <td>
  <p>N/A</p>
  </td>
  <td>
  <p>Bucket used to store DAG files.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_serviceRole</p>
  </td>
  <td>
  <p>AWS only</p>
  </td>
  <td>
  <p>IAM role ARN</p>
  </td>
  <td>
  <p>N/A</p>
  </td>
  <td>
  <p>IAM role that is used to grant
  access to required cloud services.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_storageClassName</p>
  </td>
  <td>
  <p>Yes</p>
  </td>
  <td>
  <p>gp2</p>
  </td>
  <td>
  <p>managed-csi</p>
  </td>
  <td>
  <p>Storage class that is used for
  persistent volume claims (PVCs).</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>_workloadIdentityClientId</p>
  </td>
  <td>
  <p>Azure only</p>
  </td>
  <td>
  <p>N/A</p>
  </td>
  <td>
  <p>Managed Identity Client ID</p>
  </td>
  <td>
  <p>Azure Portal &gt; Managed
  Identities &gt; &gt; Overview.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>AIRFLOW_CONN_WASB_DEFAULT
  (login/password)</p>
  </td>
  <td>
  <p>Azure only</p>
  </td>
  <td>
  <p>N/A</p>
  </td>
  <td>
  <p>Storage account name and storage
  account key</p>
  </td>
  <td>
  <p>Value that is used to create the
  default Airflow Azure Blob Storage connection.</p>
  </td>
 </tr>
 <tr>
  <td>
  <p>hostName</p>
  </td>
  <td>
  <p>Yes</p>
  </td>
  <td>
  <p>Regional endpoint</p>
  </td>
  <td>
  <p>Regional endpoint</p>
  </td>
  <td>
  <p>Value of the fleet API endpoint for your region. Configure this value in the <b>global</b>
  &gt; <b>fleets</b> section of the YAML file.</p><p>Select one of the following the fleet API gateway
  endpoints, based on your region:</p>
  <ul>
    <li><strong>United States:</strong> fleetsapigw-prod-use.ci360.sas.com</li>
    <li><strong>Europe:</strong> fleetsapigw-prod-euw.ci360.sas.com</li>
    <li><strong>Asia Pacific North:</strong> fleetsapigw-prod-apn.ci360.sas.com</li>
    <li><strong>Mumbai:</strong> fleetsapigw-prod-mum.ci360.sas.com</li>
    <li><strong>Sydney:</strong> fleetsapigw-prod-syd.ci360.sas.com</li>
    <li><strong>Training Environment:</strong> fleetsapigw-training.ci360.sas.com</li>
  </ul>
  </td>
 </tr>
 <tr>
  <td>
  <p>tenant</p>
  </td>
  <td>
  <p>Yes</p>
  </td>
  <td>
  <p>Tenant moniker</p>
  </td>
  <td>
  <p>Tenant moniker</p>
  </td>
  <td>
  <p>Configure this value in the <b>global</b>
  &gt; <b>fleets</b> section of the YAML file. This value is provided by SAS
  when the tenant is onboarded.</p>
  <p>To find the value in SAS
  Customer Intelligence 360, navigate&nbsp;<b>User Menu &gt; About</b>.</p>
  </td>
 </tr>
</table>

### Configure the Required Tools

1. Make sure that you are using Bash as the shell environment.
   * AWS CloudShell uses Bash by default.
   * In Azure Cloud Shell, select Bash as the default shell.
  
2. Connect to your Kubernetes cluster. First, sign in to your cloud account (AWS or the Azure CLI).
   Then, complete the steps below based on your provider:

   * **AWS:** Complete these steps:

     ```sh
     aws eks update-kubeconfig --name <cluster-name> --region <region>
     ```

     For example:

     ```sh
     aws eks update-kubeconfig --name aws-cluster-name --region us-east-1
     ```

   * **Azure:** Complete these steps:

        1. Make sure that you have **contributor** access.
        2. Check if azure local accounts are enabled
           ```sh
            az aks show \
            --resource-group <resource-group> \
            --name <cluster-name> \
            --query disableLocalAccounts \
            -o tsv
           ```
 
           If the command returns false, local accounts are enabled.
           
        3. If local accounts are disabled, enter this command:

           ```sh
           az aks update -g <resource-group> -n <cluster-name> --enable-local-accounts
           ```

           For example:

           ```sh
           az aks update -g azure-resource-group-name -n azure-cluster-name --enable-local-accounts
           ```

        4. Get the cluster credentials:

           ```sh
           az aks get-credentials -g <resource-group> -n <cluster-name> --admin --overwrite-existing
           ```

           For example:

           ```sh
           az aks get-credentials -g azure-resource-group-name -n azure-cluster-name --admin --overwrite-existing
           ```
 
6. Supported tools (minimum versions):

   | Tool | Minimum Version |
   |------|-----------------|
   | Helm | = 3.18.XX or 3.19.XX |
   | kubectl | >= v1.27.0 |
   | AWS CLI | >= 2.18.1 |
   | Azure CLI | >= 2.83.0 |

7. If any of the required tools are not installed or are below the minimum version, use the following steps to install them:
   
   1. Run the prerequisite script from the release archive you extracted (see [Download the Release Archive](#download-the-release-archive)):

      ```sh
      chmod +x maila-setup-prerequisites.sh
      ./maila-setup-prerequisites.sh --cloud <aws | azure>
      ```

      To view the usage options, run this command:

      ```sh
      ./maila-setup-prerequisites.sh --help
      ```

   2. Verify that the script completes successfully and that all the tools are installed with the correct versions.


### Configure the Kubernetes Environment

1. Create a namespace:

   ```sh
   kubectl create namespace <your-namespace>
   ```

   For example:

   ```sh
   kubectl create namespace user-deployment-namespace
   ```

2. Tag the namespace (as a best practice):

   ```sh
   kubectl label namespace <namespace> name=<namespace> --overwrite
   ```

3. (Azure only) Add your namespace to the Managed Identity definition.

   For Azure deployments that use Workload Identity, you must create federated credentials that bind the Kubernetes
   service accounts in your namespace to the Azure Managed Identity.

   The examples below include placeholders, which you should replace based on this information:

   | Placeholder | Description |
   |:------------|:------------|
   | < your-namespace > | the namespace you created in step 2 |
   | < azure resource group name > | the resource group that contains the Managed Identity |
   | "--issuer" | use the issuer for your AKS cluster (the region and IDs will differ) |

   Use these examples:

   ```sh
   az identity federated-credential create \
     --name "api-server-sa-<your-namespace>" \
     --identity-name "<user created Managed Identity Name>" \
     --resource-group "<azure resource group name>" \
     --issuer "<Azure cluster -> Settings -> Security Configuration -> OpenID Connect (OIDC) -> Issuer URL>" \
     --subject "system:serviceaccount:<your-namespace>:ci360-analytic-mai-airflow-api-server" \
     --audience "api://AzureADTokenExchange"
   ```

   ```sh
   az identity federated-credential create \
     --name "orchestrator-sa-<your-namespace>" \
     --identity-name "<user created Managed Identity Name>" \
     --resource-group "<azure resource group name>" \
     --issuer "<Azure cluster -> Settings -> Security Configuration -> OpenID Connect (OIDC) -> Issuer URL>" \
     --subject "system:serviceaccount:<your-namespace>:ci360-satellite" \
     --audience "api://AzureADTokenExchange"
   ```

   ```sh
   az identity federated-credential create \
     --name "airflow-worker-federated-credential-<your-namespace>" \
     --identity-name "<user created Managed Identity Name>" \
     --resource-group "<azure resource group name>" \
     --issuer "<Azure cluster -> Settings -> Security Configuration -> OpenID Connect (OIDC) -> Issuer URL>" \
     --subject "system:serviceaccount:<your-namespace>:ci360-analytic-mai-airflow-worker" \
     --audience "api://AzureADTokenExchange"
   ```


4. Create Kubernetes secrets for these values:
   * tenant ID (see <a href="https://documentation.sas.com/?cdcId=cintcdc&cdcVersion=production.a&docsetId=cintag&docsetTarget=ext-access-pts-general.htm#n0nc7m71yk4zkmn1xn1k9o9eerq2" target="_blank">Add a General Access Point</a> in the Help Center)
   * API username, password, and secret (see <a href="https://documentation.sas.com/?cdcId=cintcdc&cdcVersion=production.a&docsetId=cintag&docsetTarget=ext-access-config-apicred.htm" target="_blank">Create an API User</a> in the Help Center)

     >**Important**: Make sure that the API user follows this naming convention: `API-<tenant_moniker>-mai-<user_id>`. The local agent cannot connect if the value "mai" is not in the name.

   Use a command like this example:

   ```sh
   kubectl create secret generic <secret-name>  -n <namespace> \
      --from-literal=tenant-id=<the general access point tenant ID> \
      --from-literal=secret=<the general access point client secret> \
      --from-literal=username=<the API user definition's user ID> \
      --from-literal=password=<the API user definition's secret> \
      --from-literal=datadog-api-key=<value | this is optional and ONLY to be used while using DD as observability tool>
   ```

5. Create the secrets needed for the PostgreSQL high-availability cluster:
   
   This secret is used by the PostgreSQL High Availability (HA) statefulset to manage database security and replication.

   * **password**: This is the primary administrative password for the PostgreSQL superuser. It is required for the Airflow components to connect to and initialize the metadata database.
   * **repmgr-password**: This is used by the Replication Manager (repmgr) utility. In an HA setup, repmgr handles the failover process and standby node registration. This password allows the nodes to communicate securely to manage cluster health.

   Use a command like this example:

   ```sh
   kubectl create secret generic postgres-credentials \
     --from-literal=password="<user-defined-postgres-password>" \
     --from-literal=repmgr-password="<user-defined-repmgr-password>" \
     -n <namespace> 
   ```

   This secret is used by the Pgpool-II deployment, which acts as a load balancer and connection pooler sitting in front of the PostgreSQL nodes.

   * **admin-password**: This key is required for the Pgpool administration console and internal management. It allows Pgpool to perform health checks and manage the distribution of read/write queries across the database cluster.

   Use a command like this example:
   
   ```sh
   kubectl create secret generic pgpool-credentials \
     --from-literal=admin-password="<user-defined-pgpool-admin-password>" \
     -n <namespace>
   ```

6. Create the secret needed for Airflow:

   This secret defines the primary credentials used by the Airflow UI and API.

   * **username**: The admin username for logging into the Airflow web interface.
   * **password**: The password for the corresponding Airflow admin account.

   Use a command like this example:

   ```sh
   kubectl create secret generic airflow-auth-credentials \
     --from-literal=username="<user-defined-airflow-username>" \
     --from-literal=password="<user-defined-airflow-password>" \
     -n <namespace>
   ```

### Update the Helm values

1. Use the appropriate `values-<cloud provider>.yaml` file for your cloud provider:

   The `values-<cloud provider>.yaml` files are included in the release archive you extracted earlier (see [Download the Release Archive](#download-the-release-archive)). Navigate to the `tools/marketing-ai` directory and find:
   
   * **AWS:** `values-aws.yaml`
   * **Azure:** `values-azure.yaml`

2. Edit the file with a text editor, and update the values by using the parameter names and sample values that are described
   in the section [Collect The Required Deployment Information](https://github.com/sassoftware/ci360-helm-charts/blob/main/tools/marketing-ai/README.md#collect-the-required-deployment-information)

3. Upload the modified file through the cloud console.


### Install Service monitor CRDs

1. Check if CRDs exists:
   ```sh
   kubectl get crd servicemonitors.monitoring.coreos.com
   ```

2. Deploy CRDs if it does not exist:
   ```sh
   kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
   ```

### Validate Prerequisite Configuration

After the prerequisite steps are complete, run the validation tool to verify your configuration.

> **Important:** Do not proceed with deployment until all errors are resolved.

1. Run the prerequisite validation script from the release archive you extracted (see [Download the Release Archive](#download-the-release-archive)):

   ```sh
   chmod +x maila-validate-configuration.sh
   ./maila-validate-configuration.sh --cloud <aws | azure> --values ./values-<aws | azure>.yaml --namespace <namespace>
   ```

   Here are the examples:

   **AWS**
   ```sh
   ./maila-validate-configuration.sh --cloud aws --values ./values-aws.yaml --namespace user-deployment-namespace
   ```

   **Azure**
   ```sh
   ./maila-validate-configuration.sh --cloud azure --values ./values-azure.yaml --namespace user-deployment-namespace
   ```


## Deploy the Local Agent

### Run the Deployment Helm Script

1. Deploy the local agent through Helm.

   > **Note:** Do not use the `--wait` or `--atomic` options with this chart. These options can prevent the post‑install Jobs from
     running, which are required to complete the deployment.

   ```sh
   helm upgrade --install ci360-analytic-mai ci360-helm-charts/sas-marketing-ai \
     --version <CHART VERSION from section Set up the Helm repo> \
     --namespace <namespace created in Configure the Kubernetes Environment> \
     --values <values.yaml> \
     --timeout 20m
   ```

   For example:

   ```sh
   helm upgrade --install ci360-analytic-mai ci360-helm-charts/sas-marketing-ai \
     --version 0.39.2 \
     --namespace user-deployment-namespace \
     --values ./values-azure.yaml \
     --timeout 20m
   ```

   When you run this command:
   1. The console prints a message stating that the ci360-analytic-mai chart is
      being installed.
   2. After the chart is installed, the console prints a message that the helm chart
      is upgraded and includes information about the chart. The **Status** value should be
      `Deployed`.
   
   **Note:** If you an error occurs during this process, you must manually roll back the helm deployment to a previous revision.
   
   1. To list previous revisions, use this command:

      ```sh
      helm history ci360-analytic-mai -n <namespace>
      ```

   2. Choose one of these options:

      * For first-time deployments of the local agent, roll back to revision 1:

        ```sh
        helm rollback ci360-analytic-mai 1 -n <namespace>
        ```

      * If you are upgrading the local agent, roll back to a previous, successful deployment (for example, revision 3)

        ```sh
        helm rollback ci360-analytic-mai 3 -n <namespace>
        ```

2. Wait for pods to start before you proceed:

   ```sh
   kubectl -n <namespace created in Configure the Kubernetes Environment> wait --for=condition=ready pod --selector='!job-name' --timeout=600s
   ```
   
   The output should look this:

   ```sh
   pod/ci360-analytic-mai-airflow-api-server-585756b9c-qcgcf condition met
   pod/ci360-analytic-mai-airflow-api-server-585756b9c-rfc4p condition met
   pod/ci360-analytic-mai-airflow-dag-processor-7666bbcd5b-bwgg5 condition met
   pod/ci360-analytic-mai-airflow-dag-processor-7666bbcd5b-fn72q condition met
   pod/ci360-analytic-mai-airflow-scheduler-555784d4f4-d9czd condition met
   pod/ci360-analytic-mai-airflow-scheduler-555784d4f4-z5hj7 condition met
   pod/ci360-analytic-mai-airflow-statsd-7c9f8955d6-sj7vk condition met
   pod/ci360-analytic-mai-airflow-triggerer-0 condition met
   pod/ci360-analytic-mai-airflow-worker-6bc496db75-xc4rl condition met
   pod/ci360-analytic-mai-airflow-worker-high-memory-5f4865db64-jfzgh condition met
   pod/ci360-analytic-mai-airflow-worker-high-priority-57564856bcjjhxn condition met
   pod/ci360-analytic-mai-ci360-satellite-orchestra-67b4cc7686-s7cdt condition met
   pod/ci360-analytic-mai-ci360-satellite-orchestra-67b4cc7686-zjgc6 condition met
   pod/ci360-analytic-mai-ci360-satellite-proxy-5bb4859886-99gcn condition met
   pod/ci360-analytic-mai-ci360-satellite-proxy-5bb4859886-w28ks condition met
   pod/ci360-analytic-mai-postgresql-ha-pgpool-75f7577546-9fvl2 condition met
   pod/ci360-analytic-mai-postgresql-ha-pgpool-75f7577546-z742l condition met
   pod/ci360-analytic-mai-postgresql-ha-postgresql-0 condition met
   pod/ci360-analytic-mai-postgresql-ha-postgresql-1 condition met
   pod/ci360-analytic-mai-postgresql-ha-postgresql-2 condition met
   pod/ci360-analytic-mai-redis-node-0 condition met
   pod/ci360-analytic-mai-redis-node-1 condition met
   pod/ci360-analytic-mai-redis-node-2 condition met
   ```

### Run Helm Tests and Verify Deployment

1. Run the Helm tests by entering this command:

   ```sh
   helm test ci360-analytic-mai --namespace <your namespace> --timeout 20m &
   ```

   For example:

   ```sh
   helm test ci360-analytic-mai --namespace my-namespace-1 --timeout 20m &
   ```
   
   > **Note:** The final output of this command is the process ID, like `3528`.

   While the test job is in progress, you can inspect the logs for errors, and repeat the previous steps (if necessary) until the
   deployment is successful.
   
   To inspect the Job logs, run this command:
   
   ```sh
   kubectl logs -n <namespace> -l job-name=local-agent-test-job -f
   ```
   
   For example:
   
   ```sh
   kubectl logs -n my-namespace-1 -l job-name=local-agent-test-job -f
   ```
   
   (The `-f` option follows the logs in real time until you interrupt it (Ctrl+C).)
   
   For a successful deployment, the log files should contain entries like this example:
   
   ```sh
   [INFO] All tests PASSED successfully
   ================== Helm Test Job Completed
   ==================
   <path>$ NAME: ci360-analytic-mai
   LAST DEPLOYED: <deployment date>
   NAMESPACE: <namespace>
   STATUS: Deployed
   REVISION: 3
   TEST SUITE: local-agent-test-job
   LAST STARTED: <job start time>
   LAST COMPLETED: <job end time>
   PHASE:     Succeeded
   ```

2. Verify that these items are true:
   * All pods are in the running state.   
   * There are no CrashLoopBackOff errors.
   
3. After the deployment is complete, return to the *User's Guide* for SAS Customer Intelligence 360
   for more information about using SAS 360 Marketing AI.

<!--
### New CI360 customer
Once a new tenant is onboarded, the customer will receive a welcome email with the tenant's details
Include the additional instructions in an email to the customer with a link to the SAS public GitHub repo for Marketing AI
The remaining steps are the same as above

### Getting Started
<!--
Provide users with initial steps for getting started using your project after they have installed it.
This is a good place to include screenshots, animated GIFs, or short example videos.
-->

<!--### Running
<!--
Provide users with steps for running your project after they have installed it.
This is a good place to include screenshots, [asciinema](https://asciinema.org/) recordings, or short usage videos.
-->

<!-- ### Examples
<!--
Provide additional examples of using the software, or point to further documentation. 
Make learning and using your project as easy as possible!
-->

<!-- ### Troubleshooting
<!--
Provide workarounds and solutions to known problems.
Organize troubleshooting information using subtopics, as appropriate.
-->

## Backup and Restore

### Overview

The `local-agent` deployment includes critical data that must be preserved for operational continuity. This section describes what gets backed up, how to create backups, and how to restore from them.

#### What Gets Backed Up

A complete backup includes the following artifacts:

| Artifact | Description | Use Case | Part of Restore Script? |
|----------|-------------|----------|----------------|
| **Airflow Metadata Database (PostgreSQL)** | Complete database dump including all Airflow metadata, task history, logs, connections, variables, and pools | Migration, disaster recovery, environment cloning | Yes |
| **DAGs (Directed Acyclic Graphs)** | All workflow definitions stored in the DAGs PersistentVolumeClaim | Code preservation, workflow recovery | Yes |
| **Airflow Fernet Key** | Encryption key for Airflow secrets and sensitive connection data | Decryption of encrypted fields during restore | No. Applied at Helm installation time with --set flag |
| **Airflow Variables, Connections & Pools** | Airflow configuration objects extracted from the metadata database | Environment-specific settings, external system integrations | Yes |
| **Helm Release Values** | Current Helm deployment configuration | Configuration tracking, reproducible deployments | No. Applied at Helm installation time with -f flag |

### Backup Process

#### Prerequisites

Before running backup, ensure:
- `kubectl` is configured and authenticated to your cluster
- `helm` is installed and available in your PATH
- `tar` is available for archiving
- You have read access to the relevant Kubernetes namespace
- For cloud storage: appropriate CLI tools and authentication
  - **AWS S3**: `aws` CLI, run `aws configure`
  - **Azure Blob**: `az` CLI, run `az login`
  - **Google Cloud**: `gcloud` CLI, run `gcloud auth login`

#### Performing a Backup of Local Agent

Use the `maila-backup.sh` script to create a backup of your Local Agent configuration and data.

1. Run the backup script from the release archive you extracted (see [Download the Release Archive](#download-the-release-archive)):

   ```sh
   chmod +x maila-backup.sh
   ./maila-backup.sh --release <your-release> --namespace <your-namespace> --output <your-dir> \
      --storage-type <s3 | azure | gcs> --storage-path <storage-path>
   ```

   **Examples:**

   * **S3 backup and upload** (after: `aws configure`):
      ```sh
      ./maila-backup.sh --release ci360-analytic-mai --namespace ci360-analytic-mai --output ./backups \
         --storage-type s3 --storage-path s3://my-bucket/backups
      ```

   * **Azure backup and upload** (after: `az login`):
      ```sh
      ./maila-backup.sh --release ci360-analytic-mai --namespace ci360-analytic-mai --output ./backups \
         --storage-type azure --storage-path mycontainer@mystorageaccount
      ```

   * **Google Cloud backup and upload** (after: `gcloud auth login`):
      ```sh
      ./maila-backup.sh --release ci360-analytic-mai --namespace ci360-analytic-mai --output ./backups \
         --storage-type gcs --storage-path gs://my-bucket/backups
      ```

   **Notes:**
   - `<your-release>`: The release name that was installed with the `helm upgrade` command (e.g., `ci360-analytic-mai`)
   - `<your-namespace>`: The namespace where the release was installed (e.g., `ci360-analytic-mai`)
   - `<your-dir>`: The directory where the backup will be locally stored  (e.g., `/mai/backups/`)

   The backup file will be created in the directory specified with the `--output` flag with the format: `mai-backup-local-agent-YYYYMMDD-HHMMSS.tar.gz`.

   **Additional backup options:**
   ```bash
   --minimal         # Backup only DAGs, database, Fernet key, and Helm values (skip Airflow Variables/Connections/Pools exports)
   --dry-run         # Preview backup steps without executing
   --no-color        # Disable colored output (useful for CI/CD pipelines)
   ```

#### Backup Output

A successful backup creates a `.tar.gz` archive containing:
```
mai-backup-local-agent-20260601-173203.tar.gz
└── mai-backup-local-agent-20260601-173203/
     ├── airflow-db.sql                 # PostgreSQL dump of entire Airflow metadata database
     ├── fernet-key.txt                 # Fernet key (SENSITIVE - keep secure)
     ├── dags/                          # Complete DAGs folder contents
     ├── helm-values.yaml               # Current Helm release values snapshot
     ├── airflow-variables.json         # (Optional; skipped with --minimal)
     ├── airflow-connections.json       # (Optional; skipped with --minimal)
     └── airflow-pools.json             # (Optional; skipped with --minimal)
```

**Backup file naming:** `mai-backup-<release>-<timestamp>.tar.gz`

**Retention:**
- Store backups in multiple locations (local + cloud)
- Implement backup rotation policy (e.g., keep 7 daily, 4 weekly, 12 monthly)
- Test restore procedures regularly
#### Expected Timing

**Backup Duration:**
- **New/light namespace** (minimal DAGs, little history): ~5 minutes, ~50 KB archive
- **Production/master** (heavy DAGs, extensive task history): ~25-30 minutes, 100+ MB archive
- **Network speed to cloud storage** significantly affects upload time for large backups

### Restore from Backup

#### Prerequisites for Restore

1. **Helm release must be deployed first** — Restore only restores data, not infrastructure
   
   > **Important:** When deploying the Helm release for restore, you should apply the **Fernet key** from the backup to ensure encrypted connections and variables can be properly decrypted. This must be done at installation time. Also, if you have the `helm-values.yaml` from your backup, deploy with it to preserve all configuration.

   ```bash
   # Extract the backup archive (it contains a top-level directory)
    tar -xzf mai-backup-local-agent-<timestamp>.tar.gz
    FERNET_KEY=$(cat mai-backup-local-agent-<timestamp>/fernet-key.txt)
   
   # Deploy the Helm release with the backed-up Fernet key

   helm upgrade --install ci360-analytic-mai ci360-helm-charts/sas-marketing-ai \
     --version 0.39.2 \
     --namespace user-deployment-namespace \
     --values ./values-azure.yaml \
     -values mai-backup-local-agent-<timestamp>/helm-values.yaml \
     --set fernetKey="$FERNET_KEY" \
     --timeout 20m
   ```

2. **Backup archive must be accessible** — Either local copy or download from cloud storage

3. **Required tools:**
   - `kubectl` configured for target cluster and namespace
   - `tar` command available
   - Database must be in healthy state (deployment should be running)
   - Extracted backup archive containing `fernet-key.txt` and optionally `helm-values.yaml`

#### Performing a Restore

Use the `maila-restore.sh` script to restore your Local Agent from a backup.

**Complete restore workflow with Fernet key:**

1. Extract the backup archive and get the Fernet key:
   ```sh
   tar -xzf mai-backup-local-agent-<timestamp>.tar.gz
   FERNET_KEY=$(cat mai-backup-local-agent-<timestamp>/fernet-key.txt)
   ```

2. Deploy the Helm release with Fernet key (Step 1 of restore):
   ```sh
   helm upgrade --install ci360-analytic-mai ci360-helm-charts/sas-marketing-ai \
     --version 0.39.2 \
     --namespace user-deployment-namespace \
     --values ./values-azure.yaml \
     --set fernetKey="$FERNET_KEY" \
     --timeout 20m
   ```

3. Wait for deployment to be ready:
   ```sh
   kubectl -n user-deployment-namespace wait --for=condition=ready pod --selector='!job-name' --timeout=600s
   ```

4. Run the restore script (Step 2 of restore):
   ```sh
   chmod +x maila-restore.sh
   ./maila-restore.sh --release local-agent --namespace user-deployment-namespace --backup ./mai-backup-local-agent-<timestamp>.tar.gz
   ```

5. Verify the restoration is complete by checking pod status:
   ```sh
   kubectl get pods -n user-deployment-namespace
   ```

**Restore script options:**

1. Run the restore script from the release archive you extracted (see [Download the Release Archive](#download-the-release-archive)):

   ```sh
   chmod +x maila-restore.sh
   ./maila-restore.sh --release <your-release> --namespace <your-namespace> --backup <backup-file.tar.gz>
   ```

   > **Note:** The `<backup-file.tar.gz>` should be the backup archive created by `maila-backup.sh` (format: `mai-backup-local-agent-YYYYMMDD-HHMMSS.tar.gz`)

2. Verify the restoration is complete by checking pod status:

   ```sh
   kubectl get pods -n <your-namespace>
   ```

#### Important Restore Considerations

**Version Compatibility:**
- Restore can only be done to the **same or newer version** as the backup source
- Database schema migration happens automatically during restore, but only forward in version
- If you need to restore to an older version, consider backing up the Airflow objects (Variables, Connections, Pools) separately

**Fernet Key Mismatch:**
- If the Fernet key doesn't match during restore, encrypted connections and variables will fail to decrypt
- Always extract and apply the Fernet key from the backup when deploying the Helm release
- This is critical for restoring sensitive data like database passwords and API tokens

**Variables Created at Install Time:**
- Some variables are created during Helm installation (e.g., `partition_config`)
- These will be **overwritten** by the database restore if they exist in the backup
- To preserve install-time defaults while restoring specific DAGs only, use `--skip-db` flag

#### Expected Timing

- **Minimal backup/restore** (DAGs + DB, <1GB): 2-5 minutes
- **Full backup/restore** (with logs): 10-30+ minutes (depends on log size)
- **Network speed to cloud storage** affects upload/download time

#### Restore Failure Recovery

If the restore process fails or leaves the deployment in an inconsistent state, follow these steps:

**Option 1: Rollback Helm Deployment (Recommended)**

If the restore script encounters errors, you can roll back to the pre-restore Helm deployment:

```sh
# List previous Helm revisions
helm history ci360-analytic-mai -n <your-namespace>

# Rollback to the last known good revision (before restore)
helm rollback ci360-analytic-mai <revision-number> -n <your-namespace>

# Wait for pods to stabilize
kubectl -n <your-namespace> wait --for=condition=ready pod --selector='!job-name' --timeout=600s
```

**Option 2: Clean Reinstall**

If rollback is not viable, perform a clean reinstall:

```sh
# Delete the current Helm release
helm uninstall ci360-analytic-mai -n <your-namespace>

# Wait for all pods to terminate
kubectl -n <your-namespace> wait --for=delete pod --all --timeout=300s

# Reinstall from scratch (without backup)
helm upgrade --install ci360-analytic-mai ci360-helm-charts/sas-marketing-ai \
  --version <CHART_VERSION> \
  --namespace <your-namespace> \
  --values ./values-<cloud-provider>.yaml \
  --timeout 20m
```

**Option 3: Selective Data Recovery**

If only specific components failed, restore individual artifacts:

```sh
# Extract backup manually
tar -xzf mai-backup-local-agent-<timestamp>.tar.gz

# Restore only DAGs (skip database)
./maila-restore.sh --release <your-release> --namespace <your-namespace> \
  --backup ./mai-backup-local-agent-<timestamp> --skip-db

# Or restore only database (skip DAGs)
./maila-restore.sh --release <your-release> --namespace <your-namespace> \
  --backup ./mai-backup-local-agent-<timestamp> --skip-dags
```

**Troubleshooting Restore Failures**

- **Check pod logs:** `kubectl logs -n <namespace> <pod-name>`
- **Verify Fernet key:** Ensure the key from the backup matches what was set during Helm deployment
- **Database connectivity:** Verify PostgreSQL pods are healthy and responding
- **Storage access:** Confirm DAGs PVC is accessible and has sufficient space

## Database Maintenance for the Local Agent

When the local agent is deployed, the deployment also automatically configures a cron job to perform
maintenance on the Airflow database.

By default, the Airflow database does not delete any historical data. To improve database performance,
and to prevent excess data from being stored locally, this maintenance job removes data that is
older than 180 days.

The cron job uses the Airflow CLI, and runs the `airflow db clean` command from within the Kubernetes cluster.

These are the recurrence settings for this cron job:

* **Frequency:** Monthly
* **Day:** First Sunday of every month
* **Timing:** 02:00 AM

## Contributing

Maintainers are not currently accepting patches and contributions to this project from unapproved contributors.

If you are an approved contributor, follow these steps to update the local agent to a new version:

1. Create a personal branch to make your changes.
2. Open the `Chart.yaml` file in the `local-agent` folder and increment the version values in the Chart.yaml file (both the main version
   and versions in dependencies). This change is required because this Chart.yaml file is an umbrella chart and depends on
   other charts.
3. Submit a PR to the main branch and wait for approval.

## License
<!--
Use the default text already in place below.
Do not alter the text without prior approval from SAS Legal and the Open Source Program Office.
-->

This project is licensed under the Apache 2.0 License.

## Additional Resources

<!-- TODO: Insert link to Help Center topic -->
* <a href="https://helm.sh/docs/" target="_blank">Helm Documentation</a>
* <a href="https://kubernetes.io/docs/" target="_blank">Kubernetes Documentation</a>
* <a href="https://airflow.apache.org/docs/" target="_blank">Airflow Documentation</a>