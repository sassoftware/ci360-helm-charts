This section provides instructions to list all available Helm charts, select a desired chart, and install it.

### 1. Add the Helm repository:
   ```
   helm repo add ci360-helm-charts https://sassoftware.github.io/ci360-helm-charts/packages
   helm repo update
   ```

### 2. List the charts and versions:
   ```
  helm search repo ci360-helm-charts --versions
   ```


### 3. See package contents for a version:

   ```
  helm show readme ci360-helm-charts/marketing-ai --version 0.0.44
  helm show values ci360-helm-charts/marketing-ai --version 0.0.44
  helm show chart ci360-helm-charts/marketing-ai --version 0.0.44
   ```

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

#### c. Sample cloud-specific values.yaml:

See [values-aws.yaml](./values-aws.yaml) and [values-azure.yaml](./values-azure.yaml) for reference.

#### d. Grab the cloud-specific values.yaml:
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