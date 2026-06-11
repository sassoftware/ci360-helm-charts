# AWS Infrastructure Requirements for Local Agent

Review the information in the following sections to set up your Amazon Web Services (AWS) environment for the local agent.

1. [Kubernetes Cluster Requirements](#1-kubernetes-cluster-requirements)
2. [Configure Container Storage](#2-configure-container-storage)
3. [Identity and Access Control (IRSA)](#3-identity-and-access-control-irsa)
4. [Networking - NAT Gateway](#4-networking---nat-gateway)
5. [Additional Components](#5-additional-components)

## 1. Kubernetes Cluster Requirements

Make sure that the Kubernetes cluster meets these requirements:

| Item | Requirement / Recommendation |
|------|------------------------------|
| Kubernetes Version | >= 1.30 recommended |
| Cloud Provider | AWS (Amazon EKS) |
| Node Type | EC2-based nodes with adequate CPU/RAM |
| IAM Roles for Service Accounts (IRSA) | IAM roles inside pods (for example, Airflow to access AWS); enable IRSA in the cluster |
| EFS File System | Pre-create an Amazon EFS file system |
| EFS CSI Driver | Must be installed in the cluster |
| StorageClass for EFS | `efs-sc` – provisioned using the EFS CSI Driver |
| EBS CSI Driver | Must be installed in the cluster |
| StorageClass for GP2 | `gp2` – provisioned using the EBS CSI Driver |

### Cluster Guidelines

Follow these guidelines when you set up the cluster:

1. Set the default size of the cluster based on the size of your data volumes.
2. Configure one or more local storage volumes that contain your data.
   1. Use the S3 service to create a bucket to store the data (for example, `ci-360-data-us-east-1`).
   2. Create a folder in this bucket for logs (for example, `ci-360-data-us-east-1/logs`).
3. Make sure that you set the following IAM permissions:
   1. For the **cluster IAM role**, select the following policies:
      - `AmazonEKSBlockStoragePolicy`
      - `AmazonEKSComputePolicy`
      - `AmazonEKSLoadBalancingPolicy`
      - `AmazonEKSNetworkingPolicy`
   2. For the **node IAM role**, select the following policies:
      - `AmazonEC2ContainerRegistryReadOnly`
      - `AmazonEKS_CNI_Policy`
      - `AmazonEKSWorkerNodePolicy`

## 2. Configure Container Storage

This storage location is the base location that is used by the local agent. The application creates other subfolders as needed inside this base location.

1. Create an S3 bucket. Name the bucket using this pattern:

   ```text
   ci-360-data-<env>-<region>
   ```

   Example:

   ```text
   ci-360-data-test-us-east-1
   ```

2. Create a folder in the bucket for logs.

   Example:

   ```text
   ci-360-data-test-us-east-1/logs
   ```

3. (Recommended) Enable bucket versioning.

## 3. Identity and Access Control (IRSA)

IRSA (IAM Roles for Service Accounts) allows Kubernetes pods to securely access AWS services using IAM roles in service accounts. This enables access without requiring hardcoded AWS credentials.

### IRSA Setup Steps

Configure these parts, in order:

1. OIDC provider. Ensure your EKS cluster is associated with an OIDC provider. Required only once per cluster.
2. IAM Policy. Create an IAM policy that grants the required AWS permissions.
3. IAM Role with Trust Policy. Create an IAM role with a trust relationship that allows the EKS OIDC provider to assume the role.
4. Kubernetes Service Account (KSA). Create a Kubernetes Service Account annotated with the IAM role ARN.
5. Pod Spec. Ensure your Airflow or microservice pods are configured to use the correct KSA.

### Create IAM Policy and IAM Role for the Application

Create an IAM policy and IAM role that can be assumed by the Marketing AI application through IAM Roles for Service Accounts (IRSA).

#### Create an IAM Policy

Following is a policy for reference:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "elasticloadbalancing:*",
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": "sqs:*",
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": "s3:*",
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "ssm:GetParameters",
        "ssm:GetParameter"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
```

#### Create an IAM Role

Following is a trust policy for reference:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<oidc-id>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.<region>.amazonaws.com/id/<oidc-id>:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "oidc.eks.<region>.amazonaws.com/id/<oidc-id>:sub": [
            "system:serviceaccount:*:ci360-analytic-mai"
          ]
        }
      }
    }
  ]
}
```

> **Note:** Replace `<account-id>`, `<region>`, and `<oidc-id>` with the values corresponding to your EKS cluster.

#### Capture the IAM Role ARN

After the role is created, copy the IAM Role ARN. This ARN is required when configuring the Kubernetes Service Account for IRSA and must be referenced in the Marketing AI deployment configuration.

Example:

```text
arn:aws:iam::<account-id>:role/MAI-role-<cluster-name>-app-role
```

### IAM Permissions Required

| Permission | Purpose |
|------------|---------|
| `s3:GetObject` | Read objects from an S3 bucket |
| `s3:PutObject` | Write objects to an S3 bucket |
| `s3:DeleteObject` | Delete objects from an S3 bucket |
| `s3:ListBucket` | List contents of an S3 bucket |
| `secretsmanager:GetSecretValue` | Read secrets from AWS Secrets Manager |

## 4. Networking - NAT Gateway

Configure a NAT Gateway with a static public IP for outbound traffic. The NAT Gateway enables communication between data sources that might exist in a different cluster or cloud provider.

Complete these steps:

1. In the AWS Console, navigate to **VPC → NAT Gateways**.
2. Select **Create NAT Gateway**.
3. Select the public subnet associated with your EKS cluster.
4. Allocate or assign a static **Elastic IP address**.
5. Update the route table of the private subnets to route `0.0.0.0/0` traffic through the NAT Gateway.
6. Verify outbound connectivity from the cluster nodes.

## 5. Additional Components

### KEDA

KEDA (Kubernetes Event-Driven Autoscaling) enables event-driven or auto-scaled workloads (for example, Airflow workers).

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
