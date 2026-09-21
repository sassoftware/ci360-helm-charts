# Deploying Native Components by Using Public Helm Charts

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
  - [1. Create a Kubernetes namespace](#1-create-a-kubernetes-namespace)
  - [2. Configure your database](#2-configure-your-database)
  - [3. Use an existing PostgreSQL database](#3-use-an-existing-postgresql-database)
  - [4. Deploy PostgreSQL by using the Helm chart](#4-deploy-postgresql-by-using-the-helm-chart)
  - [5. Configure PostgreSQL backup](#5-configure-postgresql-backup)
  - [6. Create Kubernetes secrets](#6-create-kubernetes-secrets)
  - [7. Verify Helm installation](#7-verify-helm-installation)
  - [8. Verify network access](#8-verify-network-access)
- [Set up the Helm repository](#set-up-the-helm-repository)
- [Customize and deploy the Helm chart](#customize-and-deploy-the-helm-chart)
- [Deploy the Helm Chart](#deploy-the-helm-chart)
- [Verify the deployment](#verify-the-deployment)
- [Access PostgreSQL database](#access-postgresql-database)
- [Troubleshooting](#troubleshooting)

## Overview
This section provides step-by-step instructions to deploy SAS 360 Marketing Decisioning native components by using public Helm charts in a Kubernetes environment.

The deployment process supports a non-fleet model and uses Helm to simplify installation, configuration, and life cycle management of application components and their dependencies.

The Helm chart enables you to deploy the following components:
- SAS 360 Marketing Decisioning native components
- Supporting PostgreSQL database infrastructure
- Kubernetes secrets and configuration resources
- Persistent storage with optional backup configuration.

The deployment supports the following PostgreSQL configuration options:
- Using an externally managed PostgreSQL database
- Deploying PostgreSQL HA in the Kubernetes cluster by using the Bitnami PostgreSQL HA Helm chart

The deployment process includes the following tasks:
- Prepare the Kubernetes namespace
- Prepare database (external or Helm-managed)
- Create required secrets and manage credentials
- Configure the Helm repository
- Customize the values.yaml file
- Deploy the Helm chart
- Validate deployment
- Configure PostgreSQL connectivity
- Troubleshooting

## Prerequisites
Before you deploy the native components, ensure that the following requirements are met.

#### 1. Create a Kubernetes namespace
A target Kubernetes namespace(for example, testasc) must already exist. All SAS 360 Marketing Decisioning components are deployed into this namespace. If the namespace does not exist, create it.

```bash
kubectl create namespace <namespace>
```

#### 2. Configure your database
Choose one of the following methods for configuring a PostgreSQL database:
- Use an existing PostgreSQL database.
- Deploy a PostgreSQL database by using a Helm chart.

#### 3. Use an existing PostgreSQL database
**⚠️ Important:** Skip this step if you want to use a Helm chart to provision a PostgreSQL database instance.

a) Set up a PostgreSQL database:
- Ensure that a PostgreSQL database is provisioned and reachable from the Kubernetes cluster.
- You must provide the following details:
  - host (for example, postgres-service)
  - database name
  - user name and password
  - port (default: 5432)
- The database must allow connections from deployed services.

b) Initialize the database. This is a one-time task.

**⚠️ Important:** Perform this task only once. Complete it before you deploy the Helm chart.

Connect to the PostgreSQL database
```bash
psql -h <host> -U <username> -d <database>
```
Create the schema. The schema name must be contactresponse.
```sql
CREATE SCHEMA IF NOT EXISTS contactresponse;
```
Create the required tables.

Use the DDL file `CI360_ContactHistory_DDL_Scripts.sql`, available in the `tools/marketing-decisioning` folder of the `ci360-helm-charts` repository.

Verify that the tables are created:

```sql
SELECT * FROM contactresponse.subject_contact LIMIT 10;
```

**Note:** Ensure that the database schema matches `search_path=contactresponse`. The database user must have Create, Insert, Select, Update, and Delete permissions.

#### 4. Deploy PostgreSQL by using the Helm chart
**Note:** Perform this step only if you have skipped the previous step.

If you do not use an externally managed PostgreSQL database, the Helm chart provides a PostgreSQL instance during deployment. 
This approach involves the following actions:
- PostgreSQL is deployed within the Kubernetes cluster.
- The PostgreSQL deployment, including the database, schema, and persistence, is managed
through Helm values.
- The required database schema and tables are automatically created during deployment
- No external database setup is required

Before deployment, you only need to update the values.yaml file.

To enable PostgreSQL deployment, update the following section in the `values.yaml`:

```yaml
postgresql-ha:
  enabled: true
  persistence:
    enabled: true
    storageClass: "gp2"
```
Parameter Description

| Parameter | Description |
|-----------|-------------|
| `postgresql-ha.enabled` | Enables PostgreSQL deployment through Helm. |
| `persistence.enabled` | Enables persistent storage. |
| `persistence.storageClass` | `storageClass` must be set to a StorageClass available in your cluster. Examples include `gp2` (AWS), `standard` (GKE), and `managed-premium` (AKS). |

#### 5. Configure PostgreSQL backup
The backup section in `values.yaml` configures automated PostgreSQL database backups by using a Kubernetes CronJob. 
Backups are disabled by default.

```yaml
backup:
  enabled: false
```

To enable scheduled backups update the value:

```yaml
backup:
  enabled: true
```
You can then configure the backup schedule and storage settings as needed.

Backup Configuration Fields

| Field | Description | Example |
|-------|-------------|---------|
| `backup.enabled` | Enables or disables automated PostgreSQL backups. Set to `true` to create the backup CronJob. | `true` |
| `backup.cronjob.schedule` | Cron expression that defines when the backup job should run. | `"0 2 * * *"` (daily at 2:00 AM) |
| `backup.cronjob.historyLimit` | Number of completed backup job histories retained by Kubernetes. Older job records are automatically cleaned up. | `7` |
| `backup.cronjob.storage.resourcePolicy` | Controls whether the backup Persistent Volume Claim (PVC) should be preserved during Helm uninstall. Setting `keep` prevents accidental backup deletion. | `keep` |
| `backup.cronjob.storage.storageClass` | Kubernetes StorageClass used for storing backup data. The specified `storageClass` must exist in the cluster. | `"gp2"` |
| `backup.cronjob.storage.accessModes` | Defines how the backup volume can be mounted. This must be supported by the selected StorageClass. | `ReadWriteOnce` |
| `backup.cronjob.storage.size` | Size of the persistent volume allocated for storing backups. Increase this value based on your backup retention requirements. | `20Gi` |

Configuration example :

```yaml
backup:
  enabled: true
  cronjob:
    schedule: "0 2 * * *"
    historyLimit: 7
    storage:
      resourcePolicy: keep
      storageClass: "gp2"
      accessModes:
        - ReadWriteOnce
      size: 20Gi
```

### 6. Create Kubernetes secrets
You must create the required Kubernetes secrets before you deploy the Helm chart.

#### Access Point Secret
An access point secret contains configuration data that is used by API users and on-premises
agents to connect to SAS Customer Intelligence 360. The access point secret stores information
about tenant authentication.

Create the access point secret:

```bash
kubectl create secret generic access-point-secret \
  --from-literal=tenant-id=<TENANT_ID> \
  --from-literal=client-secret=<CLIENT_SECRET> \
  -n <namespace>
```
Replace <TENANT_ID>, <CLIENT_SECRET>, and <namespace> with the appropriate values for
your environment. 

#### API User Secret
The API user secret is required to generate a temporary JSON Web Token (JWT) to authenticate
some REST APIs.
Create the API user secret:

```bash
kubectl create secret generic api-user-secret \
  --from-literal=user-id=<API_USER_ID> \
  --from-literal=user-secret=<API_USER_SECRET> \
  -n <namespace>
```
Replace <API_USER_ID>, <API_USER_SECRET>, and <namespace> with the appropriate values for
your environment


#### Database Secret
Skip this step if you are deploying PostgreSQL by using a Helm chart.

Create the database secret:

```bash
kubectl create secret generic subjectcontact-db-secret \
  -n <namespace> \
  --from-literal=db.secrets="host=<DB_HOST> user=<DB_USER> password=<DB_PASSWORD> dbname=<DB_NAME> port=<DB_PORT> sslmode=<SSL_MODE> search_path=<SCHEMA>"
```

Sample command:

```bash
kubectl create secret generic subjectcontact-db-secret \
  -n testasc \
  --from-literal=db.secrets="host=postgres-service user=dbmsowner password=mypassword dbname=mydb port=5432 sslmode=disable search_path=contactresponse"
```
Replace the placeholder values (<namespace>, <DB_HOST>, <DB_USER>, <DB_PASSWORD>,
<DB_NAME>, <DB_PORT>, <SSL_MODE>, and <SCHEMA>) with the appropriate configuration for
your environment

### 7. Verify Helm installation
Verify the Helm installation:

```bash
helm version
```
### 8. Verify network access
Ensure that the Kubernetes cluster can access the following items:
- the public Helm repository
- the external API gateway that is specified by ExternalGatewayHost

**Note:** The Helm chart automatically creates the image pull secret during deployment. This secret is
used to authenticate AWS ECR to pull decision images.

## Set up the Helm repository
Add the SAS 360 Marketing Decisioning Helm repository.

```bash
helm repo add ci360-helm-charts https://sassoftware.github.io/ci360-helm-charts/packages
```
Update the Helm repository.
```bash
helm repo update
```

Verify that the chart is available:

```bash
helm search repo ci360-helm-charts/sas-marketing-decisioning
```

## Customize and deploy the Helm chart
1) Download the default Helm values file and save it locally:

```bash
helm show values ci360-helm-charts/sas-marketing-decisioning > values.yaml
```

2) Update the following parameters in `values.yaml`:

Sample values.yaml
```yaml
global:
  imagePullSecretName: image-pull-secret
  ExternalGatewayHost: "extapigwservice-demo.cidemo.sas.com"
  accessPointSecretName: access-point-secret
  apiUserSecretName: api-user-secret
  dbsecretname: subjectcontact-db-secret
```

| Parameter | Description |
|-----------|-------------|
| `imagePullSecretName` | Name of the image pull secret. The Helm chart creates this secret automatically to authenticate and pull images from AWS ECR. If this secret is missing, it causes an `ImagePullBackOff` error. |
| `ExternalGatewayHost` | External API gateway host for the target environment. |
| `accessPointSecretName` | Name of the secret that contains tenant authentication information. |
| `apiUserSecretName` | Name of the secret that contains API user credentials. |
| `dbsecretname` | Refers to the database secret used for database connectivity. If this value is incorrect, the application fails to start. |


To find the external API gateway host
- sign in to SAS Customer Intelligence 360
- go to Administration > General Settings > External Access > Access Points
- Make note of the value in the External gateway host field. This is the root URL for any API
calls that go through the external API gateway. Use the value in this field when you see the
variable <external gateway host> in the documentation..

## Deploy the Helm Chart
Before deploying, it is recommended you test (dry run) your configuration.

```bash
helm upgrade --install decisioning ci360-helm-charts/sas-marketing-decisioning \
  -n <namespace> \
  -f values.yaml \
  --dry-run
```
Replace < namespace> with the target namespace.
- If the test completes without errors, your configuration is ready for deployment.
- If errors are reported, correct them in values.yaml and repeat the test.

When the test is successful, proceed with the actual deployment by using the following
command:

```bash
helm upgrade --install <release-name> ci360-helm-charts/sas-marketing-decisioning \
  -n <namespace> \
  -f values.yaml \
  --wait --timeout 10m
```
Replace <release-name> and < namespace> with the appropriate values. The --wait and --
timeout options ensure that Helm waits for all resources to be ready before completing the
deployment.

## Verify the deployment
Check the status of the deployed resources:

```bash
kubectl get pods -n <namespace>
helm list -n <namespace>
```
Replace < namespace> with the appropriate value

Expected results:
- All pods are in the Running state.
- No pods are in the CrashLoopBackOff state.
- No pods are in the ImagePullBackOff state.

Optional: verify the image pull secret.

```bash
kubectl get secret image-pull-secret -n <namespace>
```

## Access PostgreSQL database
If you configured PostgreSQL database by using the Helm chart, you can access the database for troubleshooting purposes.

1) Retrieve database credentials:

If you need PostgreSQL database credentials, use the following values:
- Username: `postgres`
- Password: Retrieve it from the Kubernetes secret `subjectcontact-pg-auth`

To retrieve and decode the password, run the following command:

```bash
kubectl get secret subjectcontact-pg-auth -n <namespace> -o jsonpath="{.data.password}" | base64 --decode
```

2) Connect to the PostgreSQL database:

To connect to the PostgreSQL database running inside the Kubernetes cluster, use Kubernetes
port-forwarding and connect through a PostgreSQL client such as pgAdmin.

Verify PostgreSQL services.
Run the following command to list the Kubernetes services in the namespace:
```bash
kubectl get svc -n <namespace>
kubectl port-forward svc/<Release Name>-postgresql-ha-pgpool -n <namespace> 5432:5432
```
Identify the Pgpool service (<Release Name>-postgresql-ha-pgpool), which is the
recommended endpoint for PostgreSQL database connectivity.

Create a port forward to PostgreSQL
```bash
kubectl port-forward svc/<Release Name>-postgresql-ha-pgpool -n <namespace> 5432:5432
```
Connect by using pgAdmin or any PostgreSQL client.

Use the following connection details in pgAdmin or another PostgreSQL client:
- Host: `localhost`
- Port: `5432`
- Username: `postgres`
- Password: Retrieved from Kubernetes secret `subjectcontact-pg-auth`

## Troubleshooting
Troubleshoot common pod issues during deployment:
- If pods are in `ImagePullBackOff`, verify that the image pull secret exists.
```bash
kubectl get secret -n <namespace>
```
- If pods are in `CrashLoopBackOff`, check the pod logs.

```bash
kubectl logs <pod-name> -n <namespace>
```