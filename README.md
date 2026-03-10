# ci360-helm-charts

This repository provides Helm charts for deploying SAS Marketing AI and Marketing Decisioning solutions.

---

## Table of Contents

- [Marketing AI](#marketing-ai)
- [Marketing Decisioning](#marketing-decisioning)
- [Installation](#installation)
- [Samples and Tools](#samples-and-tools)
- [Support](#support)
- [Security](#security)

---

## Marketing AI

Brief overview of the Marketing AI chart, its purpose, and key features.

- Chart name: `marketing-ai`
- Latest version: `x.y.z`
- [Installation instructions](#installation)
- For chart-specific details, run:
  ```
  helm show readme marketing-ai/marketing-ai-x.y.z.tgz
  ```

---

## Marketing Decisioning

Brief overview of the Marketing Decisioning chart, its purpose, and key features.

- Chart name: `marketing-decisioning`
- Latest version: `x.y.z`
- [Installation instructions](#installation)
- For chart-specific details, run:
  ```
  helm show readme marketing-decisioning/marketing-decisioning-x.y.z.tgz
  ```

---

## Installation

1. Add the Helm repository:
   ```
   helm repo add ci360-public-repo https://sassoftware.github.io/ci360-helm-charts
   helm repo update
   ```

2. Install a chart:
   ```
   helm install marketing-ai/marketing-ai-0.0.43.tgz
   helm install marketing-decisioning/marketing-decisioning-0.0.27.tgz
   ```

---

## Samples and Tools

- See the `samples/` directory for example values files for each cloud.
- See the `tools/` directory for pre- and post-install scripts.

---

## Support

For issues or questions, please contact [support@example.com](mailto:support@example.com).

## Security

For information on reporting security vulnerabilities, see [SECURITY.md](SECURITY.md).

## License

> This project is licensed under the [Apache 2.0 License](LICENSE).

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)