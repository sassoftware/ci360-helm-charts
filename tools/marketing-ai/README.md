# Local Agent Installation for Marketing AI in SAS Customer Intelligence 360

On this page:

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Deploy the Local Agent](#deploy-the-local-agent)
* [Database Maintenance for the Local Agent](#database-maintenance-for-the-local-agent)
* [Contributing](#contributing)
* [License](#license)
* [Additional Resources](#additional-resources)

## Overview

Use SAS Marketing AI to accelerate your use of analytics. Offload the routine analysis problems that you face
so that you can free up time and resources to focus on more difficult analytical challenges. SAS Marketing AI
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

For detailed cluster requirements, node configuration, IAM permissions, and storage class
prerequisites specific to your cloud provider, see:

- <a href="./README-aws-infrastructure.md" target="_blank">AWS Infrastructure Requirements</a>
- <a href="./README-azure-infrastructure.md" target="_blank">Azure Infrastructure Requirements</a>

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
2. Check the installed Helm version:

   ```sh
   helm version --short
   ```

   **Important:** Helm v3.18.XX or v3.19.XX is required for this deployment. Verify that the output starts with v3.18.1 (for example, v3.18.1+gXXXXXXX).

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

5. Verify that you have the following tools installed, with the minimum supported versions:
   | Tool | Minimum Version |
   |------|-----------------|
   | Helm | = 3.18.XX or 3.19.XX |
   | kubectl | >= v1.27.0 |
   | AWS CLI | >= 2.18.1 |
   | Azure CLI | >= 2.83.0 |

6. Connect to your Kubernetes cluster
   
   1. Sign in to your cloud account (AWS or the Azure CLI).
      
      (Azure only) Make sure that you have **contributor** access.

   * **AWS:** Complete these steps:

     ```sh
     aws eks update-kubeconfig --name <cluster-name> --region <region>
     ```

     For example:

     ```sh
     aws eks update-kubeconfig --name aws-cluster-name --region us-east-1
     ```

   * **Azure:** Complete these steps:

        1. Check if azure local accounts are enabled
           ```sh
            az aks show \
            --resource-group <resource-group> \
            --name <cluster-name> \
            --query disableLocalAccounts \
            -o tsv
           ```
 
           If the command returns false, local accounts are enabled.
           
        2. Enable local accounts on the AKS cluster:
           >**Note**: If local account is disabled, ONLY then execute this step.

           ```sh
           az aks update -g <resource-group> -n <cluster-name> --enable-local-accounts
           ```

           For example:

           ```sh
           az aks update -g azure-resource-group-name -n azure-cluster-name --enable-local-accounts
           ```

        3. Get the cluster credentials:

           ```sh
           az aks get-credentials -g <resource-group> -n <cluster-name> --admin --overwrite-existing
           ```

           For example:

           ```sh
           az aks get-credentials -g azure-resource-group-name -n azure-cluster-name --admin --overwrite-existing
           ```

   2. If any of the required tools are not installed or are below the minimum version, use the `setup-prerequisites-tools.sh` script to install them:

      1. Download the `setup-prerequisites-tools.sh` script from this location:
         [https://github.com/sassoftware/ci360-helm-charts/blob/main/tools/marketing-ai/setup-prerequisites-tools.sh](https://github.com/sassoftware/ci360-helm-charts/blob/main/tools/marketing-ai/setup-prerequisites-tools.sh)

      2. In case you are using cloud shell, you will need to upload the file to cloudshell.
      
      3. Change the permissions to make the script executable:

         ```sh
         chmod +x setup-prerequisites-tools.sh
         ```

      4. Run the script for the appropriate cloud provider:

         ```sh
         ./setup-prerequisites-tools.sh --cloud <aws | azure>
         ```

         To view the usage options, run this command:

         ```sh
         ./setup-prerequisites-tools.sh --help
         ```

      5. Verify that the script completes successfully and all tools are installed with the correct versions.

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

     >**Note**: Make sure to use the following naming convention for API user "API-<tenant_moniker>-mai-<user_id>".

   Use a command like this example:

   ```sh
   kubectl create secret generic <secret-name>  -n <namespace> \
      --from-literal=tenant-id=<the general access point tenant ID> \
      --from-literal=secret=<the general access point client secret> \
      --from-literal=username=<the API user definition's user ID> \
      --from-literal=password=<the API user definition's secret> \
      --from-literal=datadog-api-key=<value | this is optional and ONLY to be used while using DD as observability tool>
   ```

### Set up the Helm repo
   
 1. Get the public helm repo and check the available versions:

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

2. Set configuration values.

   Download the appropriate `values-<cloud provider>.yaml` file for your cloud provider from the following location:<br>
   <a href="https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai" target="_blank">https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai</a>

   For example:
   * **AWS:** `values-aws.yaml`
   * **Azure:** `values-azure.yaml`

 3. Edit the file with a text editor, and update the values by using the parameter names and sample values that are described
   in the section [Collect The Required Deployment Information](https://github.com/sassoftware/ci360-helm-charts/blob/main/tools/marketing-ai/README.md#collect-the-required-deployment-information)

 4. Upload the modified file through the cloud console.
  

### Validate Prerequisite Configuration

After the prerequisite steps are complete, run the validation tool to verify your configuration.

> **Important:** Do not proceed with deployment until all errors are resolved.

1. Download the prerequisite validation script (`validate-configuration.sh`) from this location:<br>
   <a href="https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai" target="_blank">https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai</a>

2. Upload the script to your cloud console.

3. In the terminal, change the permissions to make the script executable:

   ```sh
   chmod +x validate-configuration.sh
   ```

4. Run the prerequisite validation script. For example:

   ```sh
   ./validate-configuration.sh --cloud <aws | azure> --values ./values-<aws | azure>.yaml --namespace <namespace>
   ```

   Here are the examples:

   **AWS**
   ```sh
   ./validate-configuration.sh --cloud aws --values ./values-aws.yaml --namespace user-deployment-namespace
   ```

   **Azure**
   ```sh
   ./validate-configuration.sh --cloud azure --values ./values-azure.yaml --namespace user-deployment-namespace
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

   If an error occurs during install or upgrade, you must manually roll back to a previous successful release.
   For example:

   ```sh
   # List previous revisions
   helm history ci360-analytic-mai -n <namespace>
   
   # Roll back to a known good revision (for example, revision 3)
   helm rollback ci360-analytic-mai 3 -n <namespace>
   ```

2. Wait for pods to start before you proceed:

   ```sh
   kubectl -n <namespace created in Configure the Kubernetes Environment> wait --for=condition=ready pod --selector='!job-name' --timeout=600s
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

   > **Note:** While the above Job is in progress, inspect the logs for errors, and repeat the previous steps (if necessary) until the deployment is successful.
   > 
   > To inspect the Job logs, run:
   > 
   > ```sh
   > kubectl logs -n <namespace> -l job-name=local-agent-test-job -f
   > ```
   > 
   > For example:
   > 
   > ```sh
   > kubectl logs -n my-namespace-1 -l job-name=local-agent-test-job -f
   > ```
   > 
   > The `-f` option follows the logs in real time until you interrupt it (Ctrl+C).

2. Verify that all of these items are true:
   * All pods are in the running state.
   * There are no CrashLoopBackOff errors.

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
