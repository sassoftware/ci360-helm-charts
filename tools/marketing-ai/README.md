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

Follow these guidelines when you create the Kubernetes cluster:

1. Set the default size of the cluster based on the size of your data volumes.
2. Configure one or more local storage volume that contain your data.
   In AWS, for example, use the S3 service to create a bucket to store the data (like `ci-360-data-us-east-1`).
   Then, create a folder in this bucket for logs (like `ci-360-data-us-east-1\logs`).
3. For AWS, make sure that you include set permissions:
   1. For the cluster's IAM role, Select the following policies:
      * AmazonEKSBlockStoragePolicy
      * AmazonEKSComputePolicy
      * AmazonEKSLoadBalancingPolicy
      * AmazonEKSNetworkingPolicy:
   2. For the node's IAM role, select the following policies:
      * AmazonEC2ContainerRegistryReadOnly
      * AmazonEKS_CNI_Policy
      * AmazonEKSWorkerNodePolicy

### Configure Container Storage

This storage location will be the base location that is used by the local agent. The application creates
other subfolders as needed inside this base location.

Follow these instructions based on your cloud-service provider:

* **AWS:**
  1. Create an S3 bucket. Name the bucket like this example:
     `ci-360-data-<env>-<region> (e.g. ci-360-data-maila-us-east-1)`
  2. (Recommended) Enable bucket versioning.

* **Azure:**
  1. Create a storage account.
  2. Create a blob container. Name the container like this example:
     `maila`
  3. (Recommended) Enable versioning.

### Configure the Required Tools in the Cluster

1. Sign in to your cloud-service provider.
2. Open a shell console for your provider:
   * AWS:
      1. Sign in to your AWS account.
      2. Enter `cloudshell` in the toolbar.
      3. Select **CloudShell** to launch the service.
   * Azure:
      1. Sign in to your Azure account and select your project (for eexample, `ci360-fleets-iso`).
      2. Go to **Settings** > **Resource Providers**.
      3. Search for `cloudshell` and select **Microsoft CloudShell**.
      4. If the Cloudshell service is not registered, click **Register** on the toolbar.
      5. Click the CloudShell icon from the toolbar (next to the Copilot icon and search bar).
   <!-- * GCP:
      1. Sign into your GCP account and select your project (for eexample, `ci360-fleets-iso`).
      2. Search for `CloudShell` in the search bar at the top of the page.
      3. Launch **Cloud Shell Editor**.
      4. After the editor opens, click **Open Terminal** from the toolbar. -->

   **Note:** You can also use a local terminal, but you will need to configure direct access credentials.

3. Install the prerequisites by using the `maila-bootstrap-tools.sh` script. This script installs the following tools:
   * git
   * helm
   * kubectl
   * python3

   To run the script:
   1. Download the `maila-bootstrap-tools.sh` script from this location: [https://github.com/sas-institute-rnd-ci360/ci360-mkt-ai-helm/tree/main/tools](https://github.com/sas-institute-rnd-ci360/ci360-mkt-ai-helm/tree/main/tools)
   2. Upload  script to your cloud environment.
      * AWS: Select **Actions** > **File upload** and follow the prompts.
      * Azure: Click the **Upload Files** icon in the CloudShell toolbar and follow the prompts.
      <!-- * GCP: From the toolbar's **More** menu (the three vertical dots), use the file upload option. -->
   3. In the shell's terminal, change the permissions to make the script executable:

      ```sh
      chmod +x maila-bootstrap-tools.sh
      ```

   4. Run the script and verify that it completes successfully:

      ```sh
      ./maila-bootstrap-tools.sh
      ```

### Configure the Kubernetes Environment

1. Connect to your Kubernetes cluster. In your cloud shell, run the following command:

   * **AWS:**

     ```sh
     aws eks update-kubeconfig --name <cluster-name> --region <region>
     ```

     For example: `aws eks update-kubeconfig --name my-cluster-us-east-1 --region us-east-1`

   * **Azure:**

     ```sh
     az aks get-credentials --resource-group <resource-group> --name <cluster-name>
     ```

     For example: `az aks get-credentials --resource-group my-cluster-rg --name ci360-dev-aks-eastus`

2. Create a namespace by entering this command:

   ```sh
   kubectl create namespace <namespace>
   ```

   For example: `kubectl create namespace myCluster-maila-prod`

3. Create Kubernetes secrets for these values:
    * tenant ID (see <a href="https://documentation.sas.com/?cdcId=cintcdc&cdcVersion=production.a&docsetId=cintag&docsetTarget=ext-access-pts-general.htm#n0nc7m71yk4zkmn1xn1k9o9eerq2" target="_blank">Add a General Access Point</a>)
    * API username, password, and secret (see <a href="https://documentation.sas.com/?cdcId=cintcdc&cdcVersion=production.a&docsetId=cintag&docsetTarget=ext-access-config-apicred.htm" target="_blank">Create an API User</a>)
    * tokenUrl and finalUrl (see <a href="https://documentation.sas.com/?cdcId=cintcdc&cdcVersion=production.a&docsetId=cintapis&docsetTarget=n03m6gnoy5kfzen1dwbedgwkikhz.htm" target="_blank">Building the Base URL for the API Calls</a>)
    * Environments credentials (it is recommended to set this through an existingSecret variable)

   Use a command like this example:

   ```sh
   kubectl create secret generic <secret-name> \
     --from-literal=tenant-id=<the general agent\'s tenant ID> \
     --from-literal=secret=<the general agent\'s client secret> \
     --from-literal=username=<the API user definition\'s user ID> \
     --from-literal=key=<the API user definition\'s secret> \
     --from-literal=password=<the API user definition\'s password> \
     --from-literal=final-url=<value> \
     --from-literal=token-url=<value> -n <namespace>
   ```

4. Set up the Helm repo. Enter these commands:

   ```sh
   helm repo add ci360-helm-charts https://sassoftware.github.io/ci360-helm-charts/packages
   helm repo update 
   helm search repo ci360-helm-charts/marketing-ai
   ```

5. Set configuration values. Use a text editor to modify one of the following files:
   * **AWS:** values-aws.yaml
   * **Azure:** values-azure.yaml
  
   ---
   **Note:** When you set these values, make sure that you verify these items:
     * the IAM role is correctly attached to the Kubernetes service account
     * access to the S3 bucket or Azure blob is valid
   ---

   The following table describes an example of variables and possible values:

   <table role="table" style="width: 100%;">
    <colgroup>
        <col span="1" style="width: 20%;">
        <col span="1" style="width: 50%;">
        <col span="1">
    </colgroup>
    <thead style="background-color: #0766d1; font-weight: bold;">
        <tr>
            <th>Parameter</th>
            <th>Sample Values for - AWS</th>
            <th>Sample Values for - Azure</th>
            <th>Description</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>
                global.storagePrefix<br>
                maiproxy.environment.MAI_INTERNAL_STORAGE_PREFIX
            </td>
            <td>s3</td>
            <td>azure</td>
            <td>This is used for storing Directed Acyclic Graphs (DAGs).</td>
        </tr>
        <tr>
            <td>global.storageBucket<br>maiproxy.environment.MAI_INTERNAL_STORAGE_BUCKET</td>
            <td>ci-360-data-local-agent</td>
            <td>mai</td>
            <td>This is used for storing DAGs in the container storage.<br><br>
                <strong>Tip:</strong> Enable versioning for the bucket.
            </td>
        </tr>
        <tr>
            <td>global.azureStorage.connectionString</td>
            <td>Not Applicable</td>
            <td>DefaultEndpointsProtocol=https;AccountName=<em>&lt;blob bucket name&gt;</em>;AccountKey=<em>&lt;account
                    key&gt;</em>;EndpointSuffix=core.windows.net</td>
            <td>This is the connection string for Azure's blob storage.</td>
        </tr>
        <tr>
            <td>airflow.config.logging.remote_base_log_folder</td>
            <td>s3://<em>&lt;global.storageBucket, MAI_INTERNAL_STORAGE_BUCKET&gt;</em>/mai/logs/local-agent<br>
                <br>For example:
                <pre>s3://ci-360-data-local-agent/mai/logs/local-agent</pre>
                </li>
            </td>
            <td>wasb://airflow-logs@<em>&lt;blob bucket name&gt;</em>.blob.core.windows.net/logs</td>
            </td>
            <td>This is used to push logs to the log folder.</td>
        </tr>
        <tr>
            <td>Change Image info:
                <ul>
                    <li>Registry</li>
                    <li>Repository</li>
                </ul>
            </td>
            <td>
                <ul>
                    <li>Registry: <em> &lt;AWS account ID&gt;</em>.dkr.ecr.<em>&lt;ECR repository
                            region&gt;</em>.amazonaws.com</li>
                    <li>Repository: <em>&lt;Repository name&gt;</em><br>For example:
                        <pre>ci360-Images-Repository</pre>
                    </li>
                </ul>
            </td>
            <td>
                <ul>
                    <li>Registry: <em>&lt;AWS account ID&gt;</em>.dkr.ecr.<em>&lt;ECR repository
                            region&gt;</em>.amazonaws.com
                    </li>
                    <li>Repository: <em>&lt;Repository name&gt;</em><br>For example:
                        <pre>ci360-Images-Repository</pre>
                    </li>
                </ul>
            </td>
            <td>
                <br>
        </tr>
        <tr>
            <td>
                <ul>
                    <li>serviceAccount.annotations</li>
                </ul>
            </td>
            <td>
                <ul>
                    <li>eks.amazonaws.com/role-arn: "arn:aws:iam::&lt;AWS account ID&gt;:role/<em>&lt;cluster role
                            name&gt;</em>"</li>
                </ul>
            </td>
            <td>azure.workload.identity/client-id: <em>&lt;Azure client Id&gt;</em><br>
                For example:
                <pre>azure.workload.identity/client-id: edb592b9-5adb-4ea4-a587-e5a56feef85b</pre>
            </td>
            <td>Enables access to cloud services</td>
        </tr>
        <tr>
            <td>
                workers.persistence.storageClassName<br>
                triggerer.persistence.storageClassName<br>
                redis.persistence.storageClassName<br>
                postgresql-ha.persistence.storageClassName
            </td>
            <td>gp2</td>
            <td>managed-csi</td>
            <td>Used for PVC creation, which acts as a hard disk inside Kubernetes</td>
        </tr>
        <tr>
            <td>ci360-satellite.dags.storageClassName</td>
            <td>efc-sc</td>
            <td>azurefile-csi</td>
            <td>Used for sharing DAGs to different pods</td>
        </tr>
        <tr>
            <td>fleets.existingSecret</td>
            <td>fleet-credentials</td>
            <td>fleet-credentials</td>
            <td>Secret name that is used to connect to the Environments service.</td>
        </tr>
        <tr>
            <td>fleets.usernamefleets.key</td>
            <td>
                <ul>
                    <li>username: "API-<api user name>"</li>
                    <li>password: "1CC7FEA244584BAB937F59"</li>
                </ul>
            </td>
            <td>
                <ul>
                    <li>username: "API-<api user name>"</li>
                    <li>password: "1CC7FEA244584BAB937F59"</li>
                </ul>
            </td>
            <td>Specify these credentials only if the credentials are not set through the fleets.existingSecret value.
            </td>
        </tr>
        <tr>
            <td>fleets.tenantfleets.hostName</td>
            <td>maitecmafleetsapigw-master.cidev.sas.us</td>
            <td>maitecmafleetsapigw-master.cidev.sas.us</td>
            <td></td>
        </tr>
    </tbody>
   </table>

### Validate Prerequisite Configuration

After you complete the prerequisite steps, run the `maila-validate-configuration.sh` script to validate your configuration.
Do not proceed with deployment until there are no errors.

1. Download the `maila-validate-configuration.sh` script from this location: [https://github.com/sas-institute-rnd-ci360/ci360-mkt-ai-helm/tree/main/tools](https://github.com/sas-institute-rnd-ci360/ci360-mkt-ai-helm/tree/main/tools)

2. Upload  script to your cloud environment.
      * AWS: Select **Actions** > **File upload** and follow the prompts.
      * Azure: Click the **Upload Files** icon in the CloudShell toolbar and follow the prompts.
      <!-- * GCP: From the toolbar's **More** menu (the three vertical dots), use the file upload option. -->

3. In the shell's terminal, change the permissions to make the script executable:

   ```sh
   chmod +x maila-validate-configuration.sh
   ```

4. In the console, run the script with one of these commends:
   * **AWS:**

   ```sh
   ./maila-validate-configuration.sh --cloud aws --values ../local-agent/values-aws.yaml --namespace <Kubernetes namespace>
   ```

   * **Azure:**

   ```sh
   ./maila-validate-configuration.sh --values ../local-agent/values-azure.yaml --namespace <Kubernetes namespace>
   ```

### Deploy the Local Agent

1. Update the Helm dependencies:

   ```sh
   helm dependency update
   ```

2. Install the Prometheus Custom Resource Definition (CRD):

   ```sh
   kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
   ```

3. Deploy the local agent through Helm:

   ```sh
   helm upgrade --install <release-name> . --namespace <your-namespace> --values values.yaml --timeout 15m
   ```

   For example:

   ```sh
   helm upgrade --install ci360-analytic-mai . --namespace agent-maitecma --create-namespace --values values-aws.yaml --timeout 20m
   ```

   **Note:** Make sure that the release name matches the patter that you used for the service account.

### Configure Airflow

Airflow enables you to programmatically author, schedule, and monitor workflows. For more information, see
[Apache Airflow](https://github.com/apache/airflow). Airflow is installed as part of the Helm deployment process.

Follow these steps to configure an Airflow connection for the `local-agent`:

1. Create a default Airflow connection:
   1. Open the Airflow UI from the Airflow API server.
   2. Navigate to **Connections**.
   3. Click **Create** to add a new connection.
   4. Complete these fields:
      * **Connection ID**: `aws_default`
      * **Connection Type**: `Amazon Web Services`
   5. Leave the default values for the other fields and click **Save**.

2. Create an Airflow variable named "partition_config":
   1. From the Airflow UI, navigate to **Admin > Variables**.
   2. Click **Create** to add a new variable.
   3. Complete these fields:
      * **Key**: `partition_config`
      * **Value**:

        ```json
        {
          "partition_extract": 1,
          "partition_size": 100000,
          "partition_summary": 0,
          "use_estimated_size": 0,
          "sample_size": 100,
          "row_size_buffer": 3.0,
          "task_memory_buffer_gb": 1.0,
          "cardinality_factor": 10
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
* Logs are written to S3 or Azure blob storage.
* Airflow connections are functional.
* DAGs are visible in the Airflow user interface.
* Connectivity is confirmed to the Fleets gateway.

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