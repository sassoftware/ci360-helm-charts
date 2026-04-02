# Local Agent Installation for Marketing AI in SAS Customer Intelligence 360

On this page:

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Installation](#installation)

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

Before you begin to set up the local agent, make sure that you have completed these steps:

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

### Configure the Required Tools

1. Verify that you have the required tools installed with the minimum supported versions:

   | Tool | Minimum Version |
   |------|-----------------|
   | Helm | = 3.18.1 |
   | kubectl | >= v1.27.0 |
   | AWS CLI | >= 2.18.1 |
   | Azure CLI | >= 2.83.0 |

2. If any of the required tools are not installed or are below the minimum version, use the `setup-prerequisites-tools.sh` script to install them:

   1. Download the `setup-prerequisites-tools.sh` script from this location: [https://github.com/sas-institute-rnd-ci360/ci360-mkt-ai-helm/tree/main/tools](https://github.com/sas-institute-rnd-ci360/ci360-mkt-ai-helm/tree/main/tools)

   2. Change the permissions to make the script executable:

      ```sh
      chmod +x setup-prerequisites-tools.sh
      ```

   3. Run the script with the appropriate cloud provider option:

      * **To install all tools for AWS:**

        ```sh
        ./setup-prerequisites-tools.sh --cloud aws
        ```

      * **To install all tools for Azure:**

        ```sh
        ./setup-prerequisites-tools.sh --cloud azure
        ```

      * **To view all available options:**

        ```sh
        ./setup-prerequisites-tools.sh --help
        ```

   4. Verify that the script completes successfully and all tools are installed with the correct versions.

### Configure the Kubernetes Environment

Run the following commands.

> **NOTE:** These steps require you to be logged in to your cloud account (AWS or Azure CLI).

1. Connect to your Kubernetes cluster.

   * **AWS:**

     ```sh
     aws eks update-kubeconfig --name <cluster-name> --region <region>
     ```

     For example:

     ```sh
     aws eks update-kubeconfig --name ci360-dev-us-east-1 --region us-east-1
     ```

   * **Azure:**

     First, enable local accounts on the AKS cluster:

     ```sh
     az aks update -g <resource-group> -n <cluster-name> --enable-local-accounts
     ```

     For example:

     ```sh
     az aks update -g ci360-analytic-mai-rg -n ci360-analytic-mai-aks --enable-local-accounts
     ```

     Then, get the cluster credentials:

     ```sh
     az aks get-credentials --resource-group <resource-group> --name <cluster-name>
     ```

     For example:

     ```sh
     az aks get-credentials --resource-group ci360-dev-rg --name ci360-dev-aks-eastus
     ```

2. Create a namespace:

   ```sh
   kubectl create namespace <your-namespace>
   ```

   For example:

   ```sh
   kubectl create namespace ci360-marketinganalytic-test
   ```

3. Tag the namespace (recommended):

   ```sh
   kubectl label namespace <namespace> name=<namespace> --overwrite
   ```

4. Create Kubernetes secrets for these values:
    * tenant ID (see <a href="https://documentation.sas.com/?cdcId=cintcdc&cdcVersion=production.a&docsetId=cintag&docsetTarget=ext-access-pts-general.htm#n0nc7m71yk4zkmn1xn1k9o9eerq2" target="_blank">Add a General Access Point</a>)
    * API username, password, and secret (see <a href="https://documentation.sas.com/?cdcId=cintcdc&cdcVersion=production.a&docsetId=cintag&docsetTarget=ext-access-config-apicred.htm" target="_blank">Create an API User</a>)

   Use a command like this example:

   ```sh
   kubectl create secret generic <secret-name> \
     --from-literal=tenant-id=<the general agent\'s tenant ID> \
     --from-literal=secret=<the general agent\'s client secret> \
     --from-literal=username=<the API user definition\'s user ID> \
     --from-literal=key=<the API user definition\'s secret> \
     --from-literal=password=<the API user definition\'s password> \
     --from-literal=datadog-api-key=<value | this is optional and ONLY to be used while using DD as observability tool> -n <namespace>
   ```

5. Set up the Helm repo. Enter these commands:

   ```sh
   # Add the repo
   helm repo add ci360-helm-charts https://sassoftware.github.io/ci360-helm-charts/packages

   # Update the repo
   helm repo update 

   # Verify that the 'marketing-ai' chart is available
   helm search repo ci360-helm-charts/marketing-ai
   ```

   To inspect the chart contents (optional), run:

   ```sh
   # Show the README for a specific chart version
   helm show readme ci360-helm-charts/marketing-ai --version <CHART VERSION from step-3.a>

   # Show the default values for a specific chart version
   helm show values ci360-helm-charts/marketing-ai --version <CHART VERSION from step-3.a>

   # Show the chart metadata for a specific chart version
   helm show chart ci360-helm-charts/marketing-ai --version <CHART VERSION from step-3.a>
   ```

6. Set configuration values.

   Download the `values-<cloud provider>.yaml` file from the following location and then edit it with a text editor:

   * https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai

   For example:
   * **AWS:** `values-aws.yaml`
   * **Azure:** `values-azure.yaml`

   Update the values in this file by using the parameter names and sample values described in the table below  
   (“The following table describes an example of variables and possible values”) as a reference for how to set each field for your environment.
  
   ---

   The following table describes an example of variables and possible values:

   <table role="table" style="width: 100%;">
     <colgroup>
       <col span="1" style="width: 20%;">
       <col span="1" style="width: 40%;">
       <col span="1" style="width: 40%;">
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
         <td></td>
       </tr>
       <tr>
         <td>_connectionString</td>
         <td>Not Applicable</td>
         <td>DefaultEndpointsProtocol=https;AccountName=&lt;blob bucket name&gt;;AccountKey=&lt;account key&gt;;EndpointSuffix=core.windows.net</td>
         <td>This is the connection string for Azure blob storage. <br> <br> How to get it in the console? Azure Console →  Blob Storage → Blob Storage Name → Security + Networking → Connection String</td>
       </tr>
       <tr>
         <td>_dagsStorageClassName</td>
         <td>efc-sc</td>
         <td>azurefile-csi</td>
         <td>Used for sharing DAGs across different pods.</td>
       </tr>
       <tr>
         <td>_externalGatewayHost</td>
         <td>extapigwservice-dev.cidev.sas.us</td>
         <td>extapigwservice-dev.cidev.sas.us</td>
         <td>You can find this value by logging into the CI360 application as admin and navigating to General settings → Access Points.</td>
       </tr>
       <tr>
         <td>_k8sAuthSecretName</td>
         <td></td>
         <td></td>
         <td>
           Name of the Kubernetes secret that you created in point&nbsp;4 of the "Configure the Kubernetes Environment" section (the namespace and secret that you created there must match this value).
         </td>
       </tr>
       <tr>
         <td>_remoteBaseLogFolder</td>
         <td>
           s3://&lt;global.storageBucket, MAI_INTERNAL_STORAGE_BUCKET&gt;/mai/logs/local-agent
           <br><br>
           For example:<br>
           <code>s3://ci-360-data-local-agent/mai/logs/local-agent</code>
         </td>
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
         <td>Enables access to cloud services. <br> <br> How to get it in the console? Azure Portal →  Managed Identities →  Select the one you have created →  Overview → client ID</td>
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
           For example:<br>
           <code>edb592b9-5adb-4ea4-a587-e5a56feef85b</code>
         </td>
         <td>Enables access to cloud services.</td>
       </tr>
       <tr>
         <td>airflow.extraEnv - AIRFLOW_CONN_WASB_DEFAULT<br>login<br>password</td>
         <td>Not Applicable</td>
         <td>
           login: &lt;input-storage-account-name-here&gt;<br>
           password: &lt;input-storage-account-key-here&gt;
         </td>
         <td>Used to create the Airflow default connection for Azure.</td>
       </tr>
       <tr>
         <td>fleets.existingSecret</td>
         <td>fleet-credentials</td>
         <td>fleet-credentials</td>
         <td>
           Name of the Kubernetes secret that you created in
           <strong>point&nbsp;4 of the "Configure the Kubernetes Environment" section</strong>
           (the namespace and secret that you created there must match this value).
         </td>
       </tr>
       <tr>
         <td>global.fleets.hostName</td>
         <td>E.g. fleetsapigw-demo.cidemo.sas.com</td>
         <td>E.g. fleetsapigw-demo.cidemo.sas.com</td>
         <td>The fleet external API gateway value provided by SAS through tenant onboarding welcome email</td>
       </tr>
       <tr>
         <td>global.fleets.tenant</td>
         <td>Tenant moniker for the tenant created on the CI360 side.</td>
         <td>Tenant moniker for the tenant created on the CI360 side.</td>
       </tr>
        <tr>
         <td>airflow.extraEnv - AIRFLOW_CONN_WASB_DEFAULT | login, password</td>
         <td>Not Applicable</td>
         <td>login: '<input-storage-account-name-here>' <br> password: '<input-storage-account-key-here></td>'
         <td>used to created Airflow default connection for Azure. <br><br> To get these values → Refer to the _connectionString login = AccountName →  <Blob Storage Name> Password = AccountKey → <String Value></td>
       </tr>
     </tbody>
   </table>

### Validate Prerequisite Configuration

Once the prerequisite steps are complete, run the validation tool to verify your configuration. **Do not proceed with deployment until all errors are resolved.**

1. Download the prerequisite validation script from this location:  
   [https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai](https://github.com/sassoftware/ci360-helm-charts/tree/main/tools/marketing-ai)  
   (file name: `validate-configuration.sh`)

2. Upload the script to your environment if needed (for example, to your Kubernetes admin node or jump host).

3. In the terminal, change the permissions to make the script executable:

   ```sh
   chmod +x validate-configuration.sh
   ```

4. Run the prerequisite validation script. Example usage:

   ```sh
   ./validate-configuration.sh --cloud <aws | azure> --values ./values-<aws | azure>.yaml --namespace <namespace from step-1.4>
   ```

   For example:

   ```sh
   ./validate-configuration.sh --cloud aws --values ./values-aws.yaml --namespace ci360-marketinganalytic-test
   ```

   or

   ```sh
   ./validate-configuration.sh --cloud azure --values ./values-azure.yaml --namespace ci360-marketinganalytic-test
   ```

### Deploy the Local Agent

Deploy the local agent through Helm:

```sh
helm upgrade --install <release name> ci360-helm-charts/marketing-ai \
  --version <CHART VERSION from section 1.6.3.a> \
  --namespace <namespace created in section 1.4> \
  --values <values.yaml> \
  --timeout 15m
```

For example:

```sh
helm upgrade --install ci360-analytic-mai ci360-helm-charts/marketing-ai \
  --version 0.0.46 \
  --namespace ci360-marketinganalytic-test \
  --values ./values-azure.yaml \
  --timeout 15m
```

After the Helm install/upgrade completes:

1. **Temporary Airflow bootstrap step**  
   Apply the temporary settings as mentioned in [Configure Airflow](#configure-airflow).  

> **NOTE**
>
> * The release name should match the service account naming pattern.
> * For **AWS**, an example is provided in the *IAM Role for Application* section.
> * For **Azure**, ensure the Kubernetes service account is annotated with the Azure Workload Identity client ID:  
>   `azure.workload.identity/client-id=<workload-identity-client-id>`.

### Configure Airflow

Airflow enables you to programmatically author, schedule, and monitor workflows. For more information, see
[Apache Airflow](https://github.com/apache/airflow). Airflow is installed as part of the Helm deployment process.

1. Create an Airflow variable named "partition_config":
   1. From the Airflow UI, navigate to **Admin > Variables**. [Admin password is set in values-<cloud>.yaml used while deployment as value of 'global.simpleAuthPassword']
   2. Click **Create** to add a new variable.
   3. Complete these fields:
      * **Key**: `partition_config`
      * **Value**:

        ```json
        {
            "partition_extract": 1,
            "partition_size": 100000,
            "partition_summary": 0,
            "use_estimated_size": 1,
            "sample_size": 100,
            "row_size_buffer": 3.0,
            "task_memory_buffer_gb": 1.0,
            "cardinality_factor": 35
        }
        ```

   4. Click **Save**.

### Run Helm Tests and Verify Deployment

1. Run the Helm tests by entering this command:

   ```sh
   helm test <release-name> --namespace <your namespace> --logs --timeout 20m &
   ```

   For example:

   ```sh
   helm test ci360-analytic-mai --namespace my-namespace-1 --logs --timeout 20m &
   ```

2. Inspect the logs for errors, and repeat the previous steps (if necessary) until the deployment is successful. To inspect the logs, you can
   use a command like this example:

   ```sh
   kubectl logs -n <namespace> -l job-name=<job name> -f
   ```

Verify that all of these items are true:

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
