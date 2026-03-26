# ci360-helm-charts

This repository provides Helm charts for deploying SAS Marketing AI and Marketing Decisioning solutions.

## Table of Contents

- [Marketing AI](#marketing-ai)
- [Marketing Decisioning](#marketing-decisioning)
- [Installation](#installation)
- [Samples and Tools](#samples-and-tools)
- [Support](#support)

## Marketing AI

CI360 Marketing Analytic Solution is a new SAS offering for providing marketing organizations with purpose-built machine learning pipelines or recipes. The solution is aimed to enable the marketers to easily run these analytics to satisfy marketing use cases (e.g. churn, next best action, etc.) wherever their data lives without the need for any data science skills. 

Marketing Analytics is one of the solutions contributing SAS' vision to leverage and deliver analytic models as software products.

### Purpose
The purpose of this helm chart is to provide Marketing AI components to be installed on customer's end.

### Key Features
- Apache Airflow
- Marketing AI Proxy
- Marketing AI Orchestrator componenets

[Installation instructions](#installation)

## Marketing Decisioning

Brief overview of the Marketing Decisioning chart, its purpose, and key features.

- Chart name: `marketing-decision-service`
- Latest version: `x.y.z`
- [Installation instructions](#installation)
- For chart-specific details, run:
  ```
  helm show readme marketing-decision-service
  ```

## Installation

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

### 4. Install a Chart

#### a. Get latest values.yaml
   ```
  helm show values ci360-helm-charts/marketing-ai --version 0.0.44 > my-values.yaml
   ```

#### b. Create namespace
   ```
   kubectl create namespace <namespace>
   ```

#### c. Create k8s credentials

   ```
   kubectl create secret generic ci360-api-credentials `
  --from-literal=tenant-id="<tenant-id>" `
  --from-literal=secret="<secret>" `
  --from-literal=username="<username>" `
  --from-literal=password="<password>" `
  --from-literal=token-url="<token-url>" `
  --from-literal=final-url="<final-url>" `
  -n <namespace>
   ```

#### d. Helm Install

   ```
   helm upgrade --install ci360-analytic-mai ci360-helm-charts/marketing-ai --version 0.0.44 --namespace <namespace> --create-namespace --values my-values.yaml --timeout 15m
   ```

## Samples and Tools

- See the `tools/` directory for pre- and post-install scripts.

## Support

For issues or questions, see [SUPPORT.md](SUPPORT.md).

## Security

For information on reporting security vulnerabilities, see [SECURITY.md](SECURITY.md).

## License

This project is licensed under the [Apache 2.0 License](LICENSE).

Using this project requires [Helm](https://helm.sh/), which is licensed with the [Apache 2.0 License]([https://helm.sh/](https://github.com/helm/helm/blob/main/LICENSE)).

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)