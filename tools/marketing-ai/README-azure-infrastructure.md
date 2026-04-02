# Azure Infrastructure Requirements for Local Agent

## 1. AKS Cluster Requirements

| Item | Requirement / Recommendation |
|------|------------------------------|
| Kubernetes Version | >= 1.30 recommended |
| Cloud Provider | Microsoft Azure (AKS) |
| Cluster Auto Scaling | Do **not** use the Azure Auto Scaling option |
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
3. Create two node pools: **App Pool** and **System Pool**.

### Node Pool Configuration

| Setting | Value |
|---------|-------|
| Minimum node count (App Pool) | 5 |
| VM size (example) | `Standard_D4s_v5` |
| Taints | None (default) |
| Labels | Optional (for scheduling) |
| Zones | Optional (depends on topology constraints) |

---

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

---

## 3. Identity and Access Control (Workload Identity)

Workload Identity allows Kubernetes pods to securely access Azure resources using managed
identities via service accounts — without hardcoding credentials.

### Managed Identity Setup

1. Create a managed identity named `aks-workload-identity-airflow`.
2. Assign the role **Storage Blob Data Contributor** to this identity on the target storage account.
3. Assign the workload identity to the storage account.

### Federated Credentials

1. In the managed identity, go to **Settings → Federated credentials**.
2. Create federated credentials for each of the following Kubernetes service accounts:

   | Service Account | Notes |
   |----------------|-------|
   | `worker` | Airflow worker pods |
   | `api-server` | API server pods |
   | `ci360-satellite` | Attached to proxy + orchestrator pods |

### Flow of Pod Access to Azure Resources

Follow these steps in order:

1. Map user credentials with the cluster (Entra ID + OIDC).
2. Assign the managed identity to the Azure storage account.
3. Create federated credentials under the managed identity.
4. Link each federated credential to the corresponding Kubernetes service account.
5. Ensure pods use those service accounts to inherit access to Azure resources.

---

## 4. Additional Components

### Networking — NAT Gateway

- Configure a static public IP for outbound traffic.
- **Purpose:** If the customer has a datasource on a different cluster or cloud, NAT is required
  for communication.

### KEDA

Add KEDA to the cluster for event-driven or auto-scaled workloads (for example, Airflow workers).

### Service Monitoring CRD

Check if the ServiceMonitor CRD exists:

```sh
kubectl get crd servicemonitors.monitoring.coreos.com
```

If it does not exist, deploy it:

```sh
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
```
