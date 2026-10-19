# GCP Infrastructure Requirements for Local Agent

Review the information in the following sections to set up your Google Kubernetes Engine (GKE) environment for the local agent.

  [GCP Infrastructure Requirements for Local Agent](#gcp-infrastructure-requirements-for-local-agent)
  1. [GKE Cluster Requirements](#1-gke-cluster-requirements)
    - [Create StorageClasses](#create-storageclasses)
      - [Step 1: Verify Prerequisites](#step-1-verify-prerequisites)
      - [Step 2: Check for Existing StorageClasses](#step-2-check-for-existing-storageclasses)
      - [Step 3: Review and Customize StorageClass Definitions](#step-3-review-and-customize-storageclass-definitions)
      - [Step 4: Apply the StorageClass Definitions](#step-4-apply-the-storageclass-definitions)
      - [Step 5: Verify Creation](#step-5-verify-creation)
      - [Step 6 (Optional): Set the Default StorageClass](#step-6-optional-set-the-default-storageclass)
      - [Cluster Guidelines](#cluster-guidelines)
  2. [Configure Container Storage](#2-configure-container-storage)
  3. [Identity and Access Control (Workload Identity)](#3-identity-and-access-control-workload-identity)
    - [Configure Workload Identity Settings](#configure-workload-identity-settings)
    - [Create the IAM Service Account and Grant Roles](#create-the-iam-service-account-and-grant-roles)
    - [Capture the Service Account Email and Project ID](#capture-the-service-account-email-and-project-id)
  4. [Object Lifecycle Cleanup Configuration](#4-object-lifecycle-cleanup-configuration)
  5. [Networking - Cloud NAT](#5-networking---cloud-nat)
  6. [Additional Components](#6-additional-components)
    - [KEDA](#keda)
    - [ServiceMonitor CRD](#servicemonitor-crd)
    - [CNPG Operator](#cnpg-operator)
  7. [Monitoring Agent](#7-monitoring-agent)

## 1. GKE Cluster Requirements

Make sure that the Kubernetes cluster meets these requirements:

| Item | Requirement / Recommendation |
|------|------------------------------|
| Kubernetes Version | >= 1.30 recommended |
| Cloud Provider | Google Cloud (GKE) |
| Cluster Mode | Standard cluster (do **not** use Autopilot) |
| Workload Identity | Enabled on the cluster (`--workload-pool`) and on each node pool (IRSA equivalent) |
| GKE Metadata Server | Enabled on every node pool that runs application pods (`--workload-metadata=GKE_METADATA`). In addition to Workload Identity, the GKE Metadata Server is required. Without these settings, pods fall back to the node's compute service account, which causes 403 errors for Cloud Storage. |
| Private Nodes | Enabled on the cluster and node pools (nodes have no public IPs; egress via Cloud NAT — see section 5) |
| Node Type | Nodes with adequate CPU/RAM (for example, `e2-standard-8`) |
| Persistent Disk CSI Driver | Must be enabled in the cluster (`pd.csi.storage.gke.io`) |
| Filestore CSI Driver | Must be enabled in the cluster (`filestore.csi.storage.gke.io`) |
| StorageClass (default) | `standard-rwo` - ReadWriteOnce, provisioned by the Persistent Disk CSI Driver |
| StorageClass for DAGs | `standard-rwx` - ReadWriteMany, provisioned by the Filestore CSI Driver |

### Create StorageClasses

Create the required StorageClasses for persistent volume management.

#### Step 1: Verify Prerequisites

Confirm that the required CSI drivers are enabled on the cluster:

```sh
kubectl get csidriver pd.csi.storage.gke.io
kubectl get csidriver filestore.csi.storage.gke.io
```

If the Filestore CSI driver is missing, enable it on the cluster:

```sh
gcloud container clusters update <cluster-name> \
  --update-addons=GcpFilestoreCsiDriver=ENABLED \
  --region=<region>
```

Also make sure the Filestore API is enabled in the project:

```sh
gcloud services enable file.googleapis.com --project=<project-id>
```

#### Step 2: Check for Existing StorageClasses

GKE clusters typically ship with a default `standard-rwo` StorageClass. Check whether it already exists:

```sh
kubectl get storageclass
```

If `standard-rwo` already exists, verify that its provisioner is `pd.csi.storage.gke.io`. You can skip creating the RWO StorageClass if the existing one meets the requirements.

#### Step 3: Review and Customize StorageClass Definitions

Review the `parameters.network` value in the RWX StorageClass and change from `default` to your VPC network name. Use these values:

* For general persistent storage, use the **ReadWriteOnce (RWO) StorageClass**:

  ```yaml
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: standard-rwo
  provisioner: pd.csi.storage.gke.io
  volumeBindingMode: WaitForFirstConsumer
  parameters:
    type: pd-standard
  allowVolumeExpansion: true
  ```

* For shared storage (DAGs and logs), use **ReadWriteMany (RWX) StorageClass**:

  ```yaml
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: standard-rwx
  provisioner: filestore.csi.storage.gke.io
  volumeBindingMode: Immediate
  parameters:
    tier: standard
    network: default
  allowVolumeExpansion: true
  ```

#### Step 4: Apply the StorageClass Definitions

Apply both StorageClasses using the provided file:

```sh
kubectl apply -f <file-containing-storage-class-configuration>.yaml
```

#### Step 5: Verify Creation

Confirm that both StorageClasses are created with the expected provisioners:

```sh
kubectl get storageclass standard-rwo standard-rwx
```

This is the expected output:

```text
NAME           PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
standard-rwo   pd.csi.storage.gke.io           Delete          WaitForFirstConsumer   true
standard-rwx   filestore.csi.storage.gke.io    Delete          Immediate              true
```

#### Step 6 (Optional): Set the Default StorageClass

If the cluster's default StorageClass value should be `standard-rwo`, annotate it in the metadata:

```sh
kubectl patch storageclass standard-rwo \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Make sure that no other StorageClass value is marked as default:

```sh
kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
```

### Cluster Guidelines

Follow these guidelines when you set up the cluster:

1. Set the default size of the cluster based on the size of your data volumes.
2. Create a dedicated node pool for the local agent workloads and record its name with private nodes enabled. For example, set up a cloud NAT gateway to communicate with the external world. The node pool name is used by the `cloud.google.com/gke-nodepool` node selector in the `values-gcp.yaml` file.

   > ⚠️ **When you create the node pool, enable all three prerequisites:** use private nodes on the cluster, Workload Identity on the cluster (`--workload-pool`), and the GKE Metadata Server on the node pool (`--workload-metadata=GKE_METADATA`). Private nodes require Cloud NAT for outbound traffic. If either Workload Identity or the GKE Metadata Server is not enabled, pods can use the node's compute service account and produce 403 errors on Cloud Storage. After the node pool is created, verify that the pool has the `metadata-server` label described in the section [3: Identity and Access Control (Workload Identity)](#3-identity-and-access-control-workload-identity).

   Use this information to configure the node pool:

   | Setting | Value |
   |---------|-------|
   | Minimum node count | 8 |
   | Machine type (recommended) | `e2-standard-8` |
   | Taints | None (default) |
   | Labels | Optional (for scheduling) |
   | Zones | Optional (depends on topology constraints) |


## 2. Configure Container Storage

This storage location is the base location that is used by the local agent. The application creates other subfolders as needed inside this base location.

1. Create a Cloud Storage bucket. Name the bucket using this pattern:

   ```text
   ci360-mai-<env>-data
   ```

   For example:

   ```text
   ci360-mai-la-data
   ```

2. Create the following prefixes (folders) in the bucket:

   | Prefix | Purpose |
   |--------|---------|
   | `mai` | Application data |
   | `mai/logs` | Airflow remote log storage |

   The Airflow remote log folder is specified as a `gs://` URI in `values-gcp.yaml`.

   For example:

   ```text
   gs://ci360-mai-la-data/mai/logs
   ```

3. (Recommended) Enable object versioning and uniform bucket-level access on the bucket.

## 3. Identity and Access Control (Workload Identity)

Workload Identity allows Kubernetes pods to securely access Google Cloud resources by binding a Kubernetes service account to an IAM service account. This enables access without requiring that you hardcode service account keys.

### Configure Workload Identity Settings

Configure these parts, in order:

1. Enable these two configurations:
   * Workload Identity on the cluster
   * GKE Metadata Server on every node pool that runs application pods.
   
   Both configurations are required. If you do not enable the metadata server for the node pool, pods bypass Workload Identity and authenticate as the node's default compute service account. This causes 403 errors on write operations to Cloud Storage (even when the IAM bindings are correct).

   To enable these settings:

   ```sh
   export PROJECT_ID=<project-id>
   export CLUSTER=<cluster-name>
   export LOCATION=<region-or-zone>

   # Enable at cluster level
   gcloud container clusters update $CLUSTER \
     --location=$LOCATION \
     --workload-pool=$PROJECT_ID.svc.id.goog \
     --project=$PROJECT_ID

   # Enable metadata server on each node pool (repeat this command for each pool)
   gcloud container node-pools update <node-pool-name> \
     --cluster=$CLUSTER --location=$LOCATION \
     --workload-metadata=GKE_METADATA \
     --project=$PROJECT_ID
   ```

   Then, verify that every application node has the label `iam.gke.io/gke-metadata-server-enabled=true`:

   ```sh
   kubectl get nodes -L iam.gke.io/gke-metadata-server-enabled
   ```

2. Create an IAM service account for the application, for example `mai-local-agent@<project-id>.iam.gserviceaccount.com`.
3. Grant the IAM service account the required roles on the bucket and project.
4. Bind the IAM service account to the Kubernetes service accounts that are used by the application by granting the `roles/iam.workloadIdentityUser` role.
5. Annotate the Kubernetes service accounts with `iam.gke.io/gcp-service-account: <iam-service-account-email>`. The Helm chart applies this annotation to the Airflow API server, workers, triggerer, and the `ci360-satellite` service account when the value is set in `values-gcp.yaml`.
6. From inside a running application pod, verify that the metadata server returns the bound IAM service account (and not the node's compute SA):

   ```sh
   kubectl -n <namespace> exec <pod> -- curl -sH "Metadata-Flavor: Google" \
     http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
   ```

   The output must match the IAM service account email from step 2.

### Create the IAM Service Account and Grant Roles

```sh
export PROJECT_ID=<project-id>
export GSA=<GSA-name>
export BUCKET=<bucket-name>

gcloud iam service-accounts create $GSA --project $PROJECT_ID

gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:$GSA@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

### Capture the Service Account Email and Project ID

After the IAM service account is created, record the service account email and the project ID. Both values are required in the deployment configuration (`gcpServiceAccount` and `projectId` in `values-gcp.yaml`).

For example:

```text
mai-local-agent@sas-01000a9f-3ce7-4a34-91bb-f6.iam.gserviceaccount.com
```

## 4. Object Lifecycle Cleanup Configuration

MAI can apply Cloud Storage lifecycle rules to eventually remove Recipe and Project artifacts after the Recipe or Project is deleted.

Lifecycle configuration is a bucket-level resource. Grant the IAM service account that is used by MAI permission to read and update the bucket lifecycle policy at bucket scope. The `roles/storage.admin` role at bucket scope satisfies this requirement. Object-level or prefix scope is not enough for lifecycle rule management.

```sh
export PROJECT_ID=<project-id>
export GSA=<GSA-name>
export BUCKET=<bucket-name>

gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:$GSA@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"
```

## 5. Networking - Cloud NAT

Configure Cloud NAT with a static external IP address for outbound traffic. Cloud NAT enables communication between data sources that might exist in a different cluster or cloud provider.

Complete these steps:

1. In the Google Cloud Console, navigate to **Network services > Cloud NAT**.
2. Select **Create Cloud NAT gateway**.
3. Select the VPC network and region associated with your GKE cluster.
4. Create or select a Cloud Router for the VPC and region.
5. Reserve and assign a static external IP address to the NAT gateway, and configure it for the GKE subnet.
6. Verify outbound connectivity from the GKE cluster nodes/pods.

## 6. Additional Components

### KEDA

KEDA (Kubernetes Event-Driven Autoscaling) enables event-driven or auto-scaled workloads, such as Airflow workers.

1. Install KEDA:

   ```sh
   helm repo add kedacore https://kedacore.github.io/charts
   helm repo update
   helm install keda kedacore/keda --namespace keda --create-namespace
   ```

2. Verify the installation:

   ```sh
   kubectl get pods -n keda
   ```

### ServiceMonitor CRD

1. Verify that the ServiceMonitor CRD exists:

   ```sh
   kubectl get crd servicemonitors.monitoring.coreos.com
   ```

2. If it does not exist, deploy it:

   ```sh
   kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
   ```

### CNPG Operator 

1. Install CNPG operator:

  ```sh
  helm repo add cnpg https://cloudnative-pg.github.io/charts
  helm repo update
  helm upgrade --install cnpg --namespace cnpg-system --create-namespace cnpg/cloudnative-pg
  ```

## 7. Monitoring Agent

The cluster must have a monitoring and observability solution enabled. Existing platforms such as Datadog, Dynatrace, New Relic, or an equivalent enterprise monitoring solution are acceptable. If no monitoring solution is currently deployed, enable Google Cloud native monitoring by using Cloud Operations for GKE (Cloud Monitoring and Cloud Logging) and Google Cloud Managed Service for Prometheus. This provides the required observability, metrics, and logging capabilities before implementation.
