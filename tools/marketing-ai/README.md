# Local Agent Installation for Marketing AI in SAS Customer Intelligence 360

On this page:

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Deploy the Local Agent](#deploy-the-local-agent)
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

After analysis is complete, only the results are sent back to SAS Customer Intelligence 360. This keeps your
data in your chosen environments while allowing you to take full advantage of the features of SAS Customer
Intelligence 360.

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

Deploy and configure a Kubernetes cluster. This cluster will be configured to connect to your
cloud-service provider. For more information, see
[https://kubernetes.io/docs/setup/](https://kubernetes.io/docs/setup/).

For detailed cluster requirements, node configuration, IAM permissions, and storage class
prerequisites specific to your cloud provider, see:

- [AWS Infrastructure Requirements](./README-aws-infrastructure.md)
- [Azure Infrastructure Requirements](./README-azure-infrastructure.md)

### Collect The Required Deployment Information
Based on the cloud provider that you will deploy the local agent, find the corresponding values in the table below. This
information is used to set configuration values later in the deployment process.

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
         <th>Sample values for - AWS</th>
         <th>Sample values for - Azure</th>
         <th>Description</th>
       </tr>
     </thead>
     <tbody>
       <tr>
         <td>_agentpool</td>
         <td>Not Applicable</td>
         <td>agentpool</td>
         <td>Traverse to AKS cluster -> settings -> node pools</td>
       </tr>
       <tr>
            <td> _storageAccountName</td>
            <td>Not Applicable</td>
            <td>Required</td>
            <td>Azure Storage Account service</td> 
       </tr>
       <tr>
         <td>_dagsStorageClassName</td>
         <td>efc-sc</td>
         <td>azurefile-csi</td>
         <td>Used for sharing DAGs across different pods.</td>
       </tr>
       <tr>
         <td>_externalGatewayHost</td>
         <td>Required</td>
         <td>Required</td>
         <td>To find this value, sign into SAS Customer Intelligence 360 (with an admin user) and navigate to <strong>General settings</strong> →  <strong>Access Points</strong>.</td>
       </tr>
       <tr>
         <td>_k8sAuthSecretName</td>
         <td>Required</td>
         <td>Required</td>
         <td>
           Name of the Kubernetes secret that you created in step 4 of the prerequisite section "Configure the Kubernetes Environment".<br><br>This value must match namespace and secret that you created during that step.
         </td>
       </tr>
       <tr>
         <td>_remoteBaseLogFolder</td>
         <td>s3://&lt;global.storageBucket, MAI_INTERNAL_STORAGE_BUCKET&gt;/mai/logs/local-agent</td>
         <td>wasb://airflow-logs@&lt;blob bucket name&gt;.blob.core.windows.net/logs</td>
         <td>Used to push logs to the log folder.</td>
       </tr>
       <tr>
         <td>_s3BucketName</td>
         <td>ci-360-data-local-agent</td>
         <td>Not Applicable</td>
         <td>Used for storing DAGs in an S3 bucket or Azure blob.</td>
       </tr>
       <tr>
         <td>_serviceRole</td>
         <td>Application service role ARN</td>
         <td>Not Applicable</td>
         <td>Enables access to cloud services. <br><br> To view this value in Azure, navigate to <strong>Azure Portal</strong> → <strong>Managed Identities</strong> → <strong>&lt;your identity&gt;</strong> → <strong>Overview</strong> → &lt;client ID&gt;.</td>
       </tr>
       <tr>
         <td>_storageClassName</td>
         <td>gp2</td>
         <td>managed-csi</td>
         <td>Used for PVC creation, which acts as a hard disk inside Kubernetes.</td>
       </tr>
       <tr>
         <td>_workloadIdentityClientId</td>
         <td>Not Applicable</td>
         <td>
           &lt;Azure client ID&gt;<br><br>
         </td>
         <td>Enables access to cloud services. <br><br> To view this value in Azure, navigate to <strong>Azure Portal</strong> → <strong>Managed Identities</strong> → <strong>&lt;your identity&gt;</strong> → <strong>Overview</strong> → &lt;client ID&gt;.</td>
       </tr>
       <tr>
         <td>airflow.extraEnv - AIRFLOW_CONN_WASB_DEFAULT<br>login<br>password</td>
         <td>Not Applicable</td>
         <td>
           login: &lt;storage account name&gt;<br>
           password: &lt;storage account key&gt;
         </td>
         <td>Used to create the Airflow default connection for Azure.</td>
       </tr>
       <tr>
         <td>fleets.existingSecret</td>
         <td>fleet-credentials</td>
         <td>fleet-credentials</td>
         <td>
           Name of the Kubernetes secret that you created in step 4 of the prerequisite section "Configure the Kubernetes Environment".<br><br>This value must match the namespace and secret that you created there.
         </td>
       </tr>
       <tr>
         <td>global.fleets.hostName</td>
         <td>Required</td>
         <td>Required</td>
         <td>External API gateway value for Fleets. This value is provided by SAS in the welcome email.</td>
       </tr>
       <tr>
         <td>global.fleets.tenant</td>
         <td>Tenant moniker for the tenant</td>
         <td>Tenant moniker for the tenant</td>
         <td>Used to authentication with the external API gateway. This value is created by SAS when the tenant is onboarded.<br><br>To find this value, in the user interface, click the user button and select <strong>About</strong>.</td>
       </tr>
        <tr>
         <td>airflow.extraEnv - AIRFLOW_CONN_WASB_DEFAULT | login, password</td>
         <td>Not Applicable</td>
         <td>login: '&lt;storage account name&gt;' <br> password: '&lt;storage account key&gt;'</td>
         <td>Used to create the default Airflow connection for Azure. <br><br> To get these values, refer to these locations:<ul><li>_connectionString login = See <strong>&lt;account name&gt;</strong> → <strong>&lt;Blob storage name&gt;</strong></li><li>password = See <strong>&lt;account key&gt;</strong> → <strong>&lt;String Value&gt;</strong></li></ul></td>
       </tr>
     </tbody>
   </table>

### Configure the Required Tools

Use one of the following options, depending on the deployment target:

* Cloud deployment:
  1. Make sure that you are using Bash as the shell environment.
        * AWS CloudShell uses Bash by default.
        * In Azure Cloud Shell, select Bash as the default shell.
  2. Check the installed Helm version:

     ```sh
     helm version --short
     ```
     **Important:** Helm v3.18.XX or v3.19.XX is required for this deployment. Verify that the output starts with v3.18.1 (for example, v3.18.1+gXXXXXXX).

     If the version is not v3.18.1 (or Helm is not installed), use the following commands to install the correct version:
  
     ```sh
     curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
     ```

     ```sh
     chmod 700 get_helm.sh
     ```
   
     ```sh
     DESIRED_VERSION=v3.18.1 ./get_helm.sh
     ```

* Local deployment or virtual machine:
   1. Verify that you have the following tools installed, with the minimum supported versions:
      | Tool | Minimum Version |
      |------|-----------------|
      | Helm | = 3.18.XX or 3.19.XX |
      | kubectl | >= v1.27.0 |
      | AWS CLI | >= 2.18.1 |
      | Azure CLI | >= 2.83.0 |

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
         ./setup-prerequisites-tools.sh --cloud < aws | azure>
         ```

         To view the usage options, run this command:

         ```sh
         ./setup-prerequisites-tools.sh --help
         ```

      5. Verify that the script completes successfully and all tools are installed with the correct versions.

### Configure the Kubernetes Environment

1. Sign in to your cloud account (AWS or the Azure CLI).
2. (Azure only) Make sure that you have **contributor** access.
3. Connect to your Kubernetes cluster.

   * **AWS:** Run the following command:

     ```sh
     aws eks update-kubeconfig --name <cluster-name> --region <region>
     ```

     For example:

     ```sh
     aws eks update-kubeconfig --name aws-cluster-name --region us-east-1
     ```

   * **Azure:** Complete these steps:

        1. Enable local accounts on the AKS cluster:

           ```sh
           az aks update -g <resource-group> -n <cluster-name> --enable-local-accounts
           ```

           For example:

           ```sh
           az aks update -g azure-resource-group-name -n azure-cluster-name --enable-local-accounts
           ```

        2. Get the cluster credentials:

           ```sh
           az aks get-credentials -g <resource-group> -n <cluster-name> --admin --overwrite-existing
           ```

           For example:

           ```sh
           az aks get-credentials -g azure-resource-group-name -n azure-cluster-name --admin --overwrite-existing
           ```

4. Create a namespace:

   ```sh
   kubectl create namespace <your-namespace>
   ```

   For example:

   ```sh
   kubectl create namespace user-deployment-namespace
   ```

5. Tag the namespace (as a best practice):

   ```sh
   kubectl label namespace <namespace> name=<namespace> --overwrite
   ```

6. (Azure only) Add your namespace to the Managed Identity definition.

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
       --subject "system:serviceaccount:<your-namespace>:<release name>-airflow-api-server" \
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
       --subject "system:serviceaccount:<your-namespace>:<release name>-airflow-worker" \
       --audience "api://AzureADTokenExchange"
     ```


8. Create Kubernetes secrets for these values:
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
   https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai

   For example:
   * **AWS:** `values-aws.yaml`
   * **Azure:** `values-azure.yaml`

 3. Edit the file with a text editor, and update the values by using the parameter names and sample values that are described
   in the section [Collect The Required Deployment Information](https://github.com/sassoftware/ci360-helm-charts/edit/main/tools/marketing-ai/README.md#collect-the-required-deployment-information)

 4. Upload the modified file through the cloud console.
  

### Validate Prerequisite Configuration

After the prerequisite steps are complete, run the validation tool to verify your configuration.

> **Important:** Do not proceed with deployment until all errors are resolved.

1. Download the prerequisite validation script (`validate-configuration.sh`) from this location:<br>
   [https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai](https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai)  

2. Upload the script to your cloud console.

3. In the terminal, change the permissions to make the script executable:

   ```sh
   chmod +x validate-configuration.sh
   ```

4. Run the prerequisite validation script. For example:

   ```sh
   ./validate-configuration.sh --cloud <aws | azure> --values ./values-<aws | azure>.yaml --namespace <namespace>
   ```

   Here is an examples:

   ```sh
   ./validate-configuration.sh --cloud aws --values ./values-< aws | azure >.yaml --namespace user-deployment-namespace
   ```


## Deploy the Local Agent

### Run the Deployment Helm Script

1. Deploy the local agent through Helm.

   > **Note:** Do not use the `--wait` or `--atomic` options with this chart. These options can prevent the post‑install Jobs from
     running, which are required to complete the deployment.

   ```sh
   helm upgrade --install <release name> ci360-helm-charts/sas-marketing-ai \
     --version <CHART VERSION from section Set up the Helm repo> \
     --namespace <namespace created in Configure the Kubernetes Environment> \
     --values <values.yaml> \
     --timeout 20m
   ```

   The release name should match the pattern for the service account name.
   * For **AWS**, an example is provided in the *IAM Role for Application* section.
   * For **Azure**, ensure the Kubernetes service account is annotated with the client ID for the Azure Workload
       Identity, like: `azure.workload.identity/client-id=<workload-identity-client-id>`.

   For example:

   ```sh
   helm upgrade --install ci360-analytic-mai ci360-helm-charts/sas-marketing-ai \
     --version 0.4.0 \
     --namespace user-deployment-namespace \
     --values ./values-azure.yaml \
     --timeout 20m
   ```

   If an error occurs during install or upgrade, you must manually roll back to a previous successful release.
   For example:

   ```sh
   # List previous revisions
   helm history <release name> -n <namespace>
   
   # Roll back to a known good revision (for example, revision 3)
   helm rollback <release name> 3 -n <namespace>
   ```

2. Wait for pods to start before you proceed:

   ```sh
   kubectl -n <namespace created in Configure the Kubernetes Environment> wait --for=condition=ready pod --selector='!job-name' --timeout=600s
   ```

### Run Helm Tests and Verify Deployment

1. Run the Helm tests by entering this command:

   ```sh
   helm test <release-name> --namespace <your namespace> --timeout 20m &
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
   > kubectl logs -n <namespace> -l job-name=<job-name> -f
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

## Contributing

Maintainers are not currently accepting patches and contributions to this project from unapproved contributors.

If you are an approved contributor, follow these steps to update the local agent to a new version:

1. Create a personal branch to make your changes.
2. Open the chart.yaml in `local-agent` folder, and increment the versions in the Chart.yaml file (both the main version
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
* [Helm Documentation](https://helm.sh/docs/)
* [Kubernetes Documentation](https://kubernetes.io/docs/)
* [Airflow Documentation](https://airflow.apache.org/docs/)
