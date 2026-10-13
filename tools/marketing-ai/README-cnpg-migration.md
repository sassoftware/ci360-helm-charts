# CloudNativePG (CNPG) Migration for Local Agent

> **Breaking change:** CloudNativePG (CNPG) is now the default PostgreSQL database architecture for Ci360-analytic-mai. Action is required for all existing deployments before you upgrade.

Review the information in the following sections to migrate your deployment from Bitnami PostgreSQL to CNPG.

- [CloudNativePG (CNPG) Migration for Local Agent](#cloudnativepg-cnpg-migration-for-local-agent)
  - [1. Choose a Deployment Path](#1-choose-a-deployment-path)
  - [2. Mandatory Prerequisites](#2-mandatory-prerequisites)
    - [Create the CNPG PostgreSQL Credentials Secret](#create-the-cnpg-postgresql-credentials-secret)
    - [Install the CNPG Operator](#install-the-cnpg-operator)
  - [3. Option A: Fresh Installation](#3-option-a-fresh-installation)
  - [4. Option B: Data Migration](#4-option-b-data-migration)
    - [Step 1: Enable Data Import](#step-1-enable-data-import)
    - [Step 2: Verify the Migration](#step-2-verify-the-migration)
    - [Step 3: Finalize the CNPG Setup](#step-3-finalize-the-cnpg-setup)
  - [5. Configuration Reference](#5-configuration-reference)

## 1. Choose a Deployment Path

Both paths require that you complete the mandatory prerequisites first.

| Path | When to Use | Data Impact |
|------|-------------|-------------|
| [Option A: Fresh Installation](#3-option-a-fresh-installation) | You do not need to retain existing recipes and projects. | All existing data is permanently deleted. |
| [Option B: Data Migration](#4-option-b-data-migration) | You must preserve existing recipes and projects. | Existing data is imported into the CNPG cluster. |

## 2. Mandatory Prerequisites

Complete both steps before you use Option A or Option B.

### Create the CNPG PostgreSQL Credentials Secret

The username must be set to `airflow`. Replace `your-postgres-password` and `your-namespace-name` with your specific values.

```sh
kubectl create secret generic cnpg-postgres-credentials \
  --from-literal=username="airflow" \
  --from-literal=password="your-postgres-password" \
  -n "your-namespace-name"
```

### Install the CNPG Operator

The CNPG operator is a mandatory requirement for your cluster.

1. Add the CNPG Helm repository.

   ```sh
   helm repo add cnpg https://cloudnative-pg.github.io/charts
   ```

2. Update the Helm repositories.

   ```sh
   helm repo update
   ```

3. Install the operator in a dedicated namespace (`cnpg-system` is recommended).

   ```sh
   helm upgrade --install cnpg --namespace cnpg-system --create-namespace cnpg/cloudnative-pg
   ```

4. Verify that the operator pod is running.

   ```sh
   kubectl get pods -n cnpg-system
   ```

## 3. Option A: Fresh Installation

> **Data loss warning:** Choose this path only if you do not need to retain existing data. A fresh setup permanently deletes all existing recipes and projects.

1. Complete the [Mandatory Prerequisites](#2-mandatory-prerequisites).
2. Confirm that your `values-<cloud-provider>.yaml` file uses the default values.

   ```yaml
   _postgresHA_enabled: &postgresHAEnabled false
   _cnpg_enabled: &cnpgEnabled true
   _importFrom_enabled: &importFromEnabled false
   ```

3. Run your standard `helm upgrade --install` deployment command.

## 4. Option B: Data Migration

Use this path to migrate your existing Bitnami PostgreSQL data into the new CNPG architecture.

> **Downtime required:** Schedule approximately one hour of downtime. No new data can be written to the existing Bitnami PostgreSQL database during this window. If writes are not halted, the result is data inconsistency and missing recipes or projects.

This migration requires that you run the Helm deployment command twice: first to import the data, and again to disable the import feature.

### Step 1: Enable Data Import

1. In your `values-<cloud-provider>.yaml` file, enable HA, CNPG, and the import feature.

   ```yaml
   _postgresHA_enabled: &postgresHAEnabled true
   _cnpg_enabled: &cnpgEnabled true
   _importFrom_enabled: &importFromEnabled true
   ```

2. Run your standard Helm deployment command.

### Step 2: Verify the Migration

Wait for the Helm upgrade to complete. Before you continue to Step 3, you must:

1. Verify that all pods are up and running successfully.

   ```sh
   kubectl get pods -n "your-namespace-name"
   ```

2. Log in to the application and verify that all existing data, recipes, and projects migrated to the new setup.

### Step 3: Finalize the CNPG Setup

1. After data verification is complete, update your `values-<cloud-provider>.yaml` file to disable the import and legacy HA flags.

   ```yaml
   _postgresHA_enabled: &postgresHAEnabled false
   _cnpg_enabled: &cnpgEnabled true
   _importFrom_enabled: &importFromEnabled false
   ```

2. Run your standard Helm deployment command.

## 5. Configuration Reference

| Value | Fresh Installation | Migration (Step 1) | Migration (Step 3) | Purpose |
|-------|--------------------|--------------------|--------------------|---------|
| `_postgresHA_enabled` | `false` | `true` | `false` | Keeps the legacy Bitnami PostgreSQL HA deployment available as the migration source. |
| `_cnpg_enabled` | `true` | `true` | `true` | Deploys the CNPG PostgreSQL cluster. |
| `_importFrom_enabled` | `false` | `true` | `false` | Imports data from the Bitnami PostgreSQL database into the CNPG cluster. |

> **Important:** Set `_postgresHA_enabled` and `_importFrom_enabled` to `true` only during the first CNPG installation. Set both values back to `false` and redeploy after you verify that your data migrated and that your recipes and projects are visible.
