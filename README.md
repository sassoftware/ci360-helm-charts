# ci360-helm-charts

This repository provides Helm charts for deploying SAS Marketing AI and Marketing Decisioning solutions.

---

## Table of Contents

- [Marketing AI](#marketing-ai)
- [Marketing Decisioning](#marketing-decisioning)
- [Installation](#installation)
- [Samples and Tools](#samples-and-tools)
- [Support](#support)

---

## Marketing AI

Brief overview of the Marketing AI chart, its purpose, and key features.

- Chart name: `marketing-ai-service`
- Latest version: `x.y.z`
- [Installation instructions](#installation)
- For chart-specific details, run:
  ```
  helm show readme marketing-ai-service
  ```

---

## Marketing Decisioning

Brief overview of the Marketing Decisioning chart, its purpose, and key features.

- Chart name: `marketing-decision-service`
- Latest version: `x.y.z`
- [Installation instructions](#installation)
- For chart-specific details, run:
  ```
  helm show readme marketing-decision-service
  ```

---

## Installation

1. Add the Helm repository:
   ```
   helm repo add ci360 https://<org>.github.io/<repo>
   helm repo update
   ```

2. Install a chart:
   ```
   helm install my-ai-release ci360/marketing-ai-service
   helm install my-decision-release ci360/marketing-decision-service
   ```

---

## Samples and Tools

- See the `samples/` directory for example values files for each cloud.
- See the `tools/` directory for pre- and post-install scripts.

---

## Support

For issues or questions, please contact [support@example.com](mailto:support@example.com).
