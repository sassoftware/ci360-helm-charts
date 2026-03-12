# Marketing AI

## Pre-requisites
1. Cluster with 
- workload identity binding for GCP
- sufficiently big node pool
- correct mode (system/user) in ACP


2. Bucket 

3. Service Account / Role and IAM Binding

Perhaps include a generic or cloud-specific pre-requisite section or point to tools.

### Pre-requisite validation
Script for validating pre-requisites are created correctly. 

## Steps for installing Umbrella chart 'local-agent'
This section provides instructions to list all available Helm charts, select a desired chart, and install it.

### 1. Add ci-360 as a helm repo
```sh
helm repo add ci360-helm-local <https://ci360-helm-charts-public-GH-url>
```

### 2. List all charts:
   Run the following commands to view currently installed charts and update dependencies:
```sh
helm list
helm dependency update
```
   To see charts available for installation, browse the chart repository or directory (e.g., `ls charts/`).

### 3. Pick a chart:
   Review the list and choose the chart you want to install, say, `marketing-ai-0.0.43`.

### 4. Overriding parameters

#### a. Using `--set` parameter:
```sh
helm upgrade --install <release-name> <chart-name> --set global.storageBucket="your-new-bucket-name"
```

#### b. Using values.yaml:
```sh
helm show values marketing-ai/marketing-ai-0.0.43.tgz > custom-values.yaml
helm upgrade --install <release-name> <chart-name> --values custom-values.yaml
```

#### c. Grab the cloud-specific values.yaml:
   - Download the desired chart archive (e.g., `marketing-ai-0.0.43.tgz`).
   - Unpack the archive:
```sh
tar -xzf marketing-ai-0.0.43.tgz
```
   - Locate the cloud-specific values file:
     - For GCP: `marketing-ai/values-gcp.yaml`
     - For AWS: `marketing-ai/values-aws.yaml`
     - For Azure: `marketing-ai/values-azure.yaml`
   - Use the appropriate file to override default values during installation:
```sh
helm install <release-name> <chart-path> --values marketing-ai/values-gcp.yaml
```

### 5. Install and test the chart:
   Use the command:
```sh
helm install <release-name> <chart-path>
```
   Replace `<release-name>` with your chosen name for the deployment.
   Replace `<chart-path>` with the path or name of the chart.

Example:
```sh
helm upgrade --install <release-name> marketing-ai/marketing-ai-0.0.43 --namespace <your-namespace> --create-namespace --values values.yaml --timeout 15m
```
   Complete the steps mentioned in the `Airflow Configuration` section below.
```sh
helm test <release-name> --namespace <your-namespace> --logs --timeout 20m &
kubectl logs -n <your-namespace> -l job-name=local-agent-test-job -f
```
   Here, the release name is `<release-name>`, and the namespace is `<your-namespace>`. Replace `<release-name>` with your desired release name and `<your-namespace>` with the namespace you want to use.

## Steps for configuring 'local-agent' on dev cluster
- Change `serviceAccount` annotations in the `values.yaml` file.
- Update `MAI_INTERNAL_STORAGE_BUCKET` and `global.storageBucket`.

### Airflow Configuration
Follow these steps to configure Airflow for the `local-agent`:

1. **Create a Default Airflow Connection**:
   - Open the Airflow UI from the Airflow API server.
   - Navigate to the **Connections** section.
   - Click on the **Create** button to add a new connection.
   - Fill in the following details:
     - **Connection ID**: `aws_default`
     - **Connection Type**: `Amazon Web Services`
   - Leave other fields as default and click **Save**.

2. **Create an Airflow Variable**:
   - Open the Airflow UI from the Airflow API server.
   - Navigate to the **Admin > Variables** section.
   - Click on the **Create** button to add a new variable.
   - Fill in the following details:
     - **Key**: `partition_config`
     - **Value**:
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
   - Click **Save**.

## Contributing
Maintainers are not currently accepting patches and contributions to this project.

## License

This project is licensed under the [Apache 2.0 License](https://github.com/helm/helm/blob/main/LICENSE).

## Additional Resources
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Airflow Documentation](https://airflow.apache.org/docs/)