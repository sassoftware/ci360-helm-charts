# Azure Infrastructure Requirements for Local Agent

Review the information in the following sections to set up your Amazon Web Services (AWS) environment for the local agent.

1. [AKS Cluster Requirements](#1-aks-cluster-requirements)
2. [Configure Container Storage](#2-configure-container-storage)
3. [Identity and Access Control (Workload Identity)](#3-identity-and-access-control-workload-identity)
4. [Additional Components](#4-additional-components)

## 1. AKS Cluster Requirements

| Item | Requirement / Recommendation |
|------|------------------------------|
| Kubernetes Version | >= 1.30 recommended |
| Cloud Provider | Microsoft Azure (AKS) |
| Cluster Auto Scaling | Do **not** use the Automatic Kubernetes Cluster option while creating the cluster |
| Authentication Mode | Microsoft Entra ID authentication with Kubernetes RBAC |
| OIDC | Enabled (required for Workload Identity) |
| Workload Identity | Enabled (IRSA equivalent) |
| StorageClass (default) | `kubernetes.io/azure-disk` |
| StorageClass for DAGs | `managed-csi` – provisioner: `disk.csi.azure.com` |
| StorageClass for file storage | `azurefile-csi` – provisioner: `file.csi.azure.com` |

### Cluster Guidelines

1. Set the default size of the cluster based on the size of your data volumes.
2. Configure storage volumes that contain your data.
   Use Azure Blob Storage to create a container to store the data
   (for example, `marketinganalytic`).
3. Create two node pools: **User Node Pool** and **System Node Pool**.

   Use this information to configure the node pools:

   | Setting | Value |
   |---------|-------|
   | Minimum node count (User Node Pool) | 8 |
   | Minimum node count (System Node Pool) | 1 |
   | VM size (recommended) | `Standard_D4s_v5` |
   | Taints | None (default) |
   | Labels | Optional (for scheduling) |
   | Zones | Optional (depends on topology constraints) |


## 2. Configure Container Storage

This storage location is the base location used by the local agent. The application creates
other subfolders as needed inside this base location.

1. Create a storage account.
2. Create the following blob containers inside the storage account:

   | Container Name | Purpose |
   |---------------|---------|
   | `marketinganalytic` | Primary data storage |
   | `mai` | Application data |
   | `airflow-logs` | Airflow log storage |

3. Set the RBAC role **Storage Blob Data Contributor** on each container.
4. (Recommended) Enable versioning on the storage account.


## 3. Identity and Access Control (Workload Identity)

Workload Identity allows Kubernetes pods to securely access Azure resources using managed identities
through service accounts. This enables access without requiring that you hardcode Azure credentials.

### Managed Identity Setup

1. Create a managed identity named `aks-workload-identity-airflow`.
2. Assign the role **Storage Blob Data Contributor** to this identity on the target storage account.
3. Assign the workload identity to the storage account.

### Flow of Pod Access to Azure Resources

Follow these steps:

1. Map user credentials with the cluster (Entra ID + OIDC).
2. Assign the managed identity to the Azure storage account.
3. Create federated credentials under the managed identity.
4. Link each federated credential to the corresponding Kubernetes service account.
5. Ensure pods use those service accounts to inherit access to Azure resources.

## 4. Additional Components

### Networking — NAT Gateway

Configure a static public IP for outbound traffic.

A public IP address and NAT enables communication between data sources that might exist in a different cluster or cloud provider.

### KEDA

Add KEDA to the cluster for event-driven or auto-scaled workloads (for example, Airflow workers).
1. Add KEDA Helm Repository
```sh
helm repo add kedacore https://kedacore.github.io/charts
```
2. helm repo update
```sh
helm repo update
```
4. Install KEDA using Helm
Note: Install the KEDA operator in a dedicated namespace (keda is recommended).
```sh
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace
```
5. Verify Installation
Check that the KEDA operator and metrics server pods are running.
```sh
kubectl get pods -n keda
```

### Service Monitoring CRD

1. Verify that the ServiceMonitor CRD exists:

   ```sh
   kubectl get crd servicemonitors.monitoring.coreos.com
   ```

2. If it does not exist, deploy it:

   ```sh
   kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
   ```
