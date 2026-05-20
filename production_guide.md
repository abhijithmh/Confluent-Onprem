# Moving Confluent + NiFi to Production

## Current State vs Production Target

| Aspect | Current (Local Dev) | Production Target |
|---|---|---|
| Kafka nodes | 1 combined broker+controller | 3+ brokers, 3 controllers (KRaft) |
| Replication factor | 1 | 3 |
| NiFi nodes | 1 standalone | 3-node cluster |
| Security | None / self-signed TLS | mTLS + SASL/SCRAM or LDAP |
| Persistence | Docker named volumes | Cloud PVCs / managed storage |
| Secrets | Env vars in compose | Vault / K8s Secrets / AWS SM |
| Deployment | Docker Compose | Kubernetes (CFK) or managed cloud |

---

## Option 1: Kubernetes with Confluent for Kubernetes (CFK) ⭐ Recommended

You already have the CFK manifests (`kafka.yaml`, `kraft-controller.yaml`, `controlcenter.yaml`). This is the most direct path.

### Step 1 — Provision a Kubernetes cluster

```bash
# AWS EKS
eksctl create cluster --name confluent-prod --region ap-south-1 \
  --nodegroup-name kafka-nodes --node-type m5.2xlarge --nodes 3

# Azure AKS
az aks create -g my-rg -n confluent-prod --node-count 3 --node-vm-size Standard_D4s_v3

# GKE
gcloud container clusters create confluent-prod --num-nodes 3 --machine-type e2-standard-4
```

### Step 2 — Install Confluent for Kubernetes operator

```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

kubectl create namespace confluent

helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes \
  --namespace confluent \
  --set kRaftEnabled=true
```

### Step 3 — Apply your manifests (with production hardening)

```bash
kubectl apply -f Manifest\ Files/kraft-controller.yaml -n confluent
kubectl apply -f Manifest\ Files/kafka.yaml -n confluent
kubectl apply -f Manifest\ Files/schema-registry.yaml -n confluent
kubectl apply -f Manifest\ Files/controlcenter.yaml -n confluent
```

### Step 4 — Scale up replicas (edit your manifests)

```yaml
# kraft-controller.yaml
spec:
  replicas: 3        # was 1

# kafka.yaml
spec:
  replicas: 3        # was 1
  configOverrides:
    server:
      - "default.replication.factor=3"
      - "min.insync.replicas=2"
      - "offsets.topic.replication.factor=3"
      - "transaction.state.log.replication.factor=3"
```

---

## Option 2: Managed Cloud (Fastest Path)

| Provider | Service | Notes |
|---|---|---|
| Confluent Cloud | Fully managed Kafka + Schema Registry | Pay-per-use, zero ops |
| AWS MSK | Managed Kafka | Good AWS integration |
| Azure Event Hubs | Kafka-compatible | Good if already on Azure |
| GCP Pub/Sub | Kafka-compatible via connector | |

```bash
# Confluent Cloud CLI
confluent kafka cluster create prod-cluster \
  --cloud aws --region ap-south-1 \
  --type dedicated --cku 2
```

---

## Option 3: Self-managed VMs (Docker Compose on servers)

For smaller teams — run Docker Compose on Linux VMs with external storage.

```
VM 1: kafka + kraft-controller
VM 2: kafka + kraft-controller  
VM 3: kafka + kraft-controller (quorum)
VM 4: schema-registry + control-center
VM 5: nifi node 1
VM 6: nifi node 2
```

---

## Critical Security Hardening (All Options)

### 1. TLS everywhere

```yaml
# In your CFK kafka.yaml
spec:
  tls:
    secretRef: kafka-tls-secret   # cert-manager or manual
```

### 2. Authentication — SASL/SCRAM

```yaml
# kafka.yaml
spec:
  listeners:
    external:
      authentication:
        type: mtls   # or sasl/scram-sha-512
```

### 3. Secrets — never use plain env vars in production

```bash
# Kubernetes secrets
kubectl create secret generic kafka-credentials \
  --from-literal=username=admin \
  --from-literal=password='<strong-password>' \
  -n confluent

# Or use External Secrets Operator with AWS Secrets Manager / Vault
helm install external-secrets external-secrets/external-secrets -n external-secrets
```

### 4. Network policies

```yaml
# Only allow pods in 'confluent' namespace to reach kafka:9092
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kafka-allow-confluent-ns
  namespace: confluent
spec:
  podSelector:
    matchLabels:
      app: kafka
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: confluent
```

---

## NiFi Cluster in Production

```yaml
# nifi-statefulset.yaml (3-node cluster via ZooKeeper or embedded)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: nifi
spec:
  replicas: 3
  serviceName: nifi
  template:
    spec:
      containers:
        - name: nifi
          image: apache/nifi:2.2.0
          env:
            - name: NIFI_CLUSTER_IS_NODE
              value: "true"
            - name: NIFI_ZK_CONNECT_STRING
              value: "zookeeper:2181"
            - name: NIFI_CLUSTER_NODE_PROTOCOL_PORT
              value: "11443"
```

> [!TIP]
> For NiFi on Kubernetes, use the **Apache NiFi Operator** or **Cloudera Flow Management** for enterprise clustering.

---

## Persistent Storage (Production)

```yaml
# Storage class for Kafka (AWS EBS gp3)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: kafka-storage
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
reclaimPolicy: Retain    # ← NEVER Delete for Kafka
allowVolumeExpansion: true
```

```yaml
# In your kafka.yaml CFK manifest
spec:
  dataVolumeCapacity: 500Gi
  storageClass:
    name: kafka-storage
```

---

## CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy Confluent Stack
on:
  push:
    branches: [main]
    paths: ['Manifest Files/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/setup-kubectl@v3
      - name: Apply manifests
        run: |
          kubectl apply -f "Manifest Files/" -n confluent
          kubectl rollout status statefulset/kafka -n confluent
```

---

## Monitoring Stack

```bash
# Add Prometheus + Grafana via Helm
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.enabled=true \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Confluent provides official Grafana dashboards:
# https://github.com/confluentinc/jmx-monitoring-stacks
```

---

## Production Readiness Checklist

- [ ] **3+ Kafka brokers** with replication factor 3
- [ ] **3 KRaft controllers** (separate from brokers)
- [ ] **TLS** on all listener ports
- [ ] **SASL/SCRAM or mTLS** authentication
- [ ] **Secrets** in Vault / K8s Secrets (not env vars)
- [ ] **Network policies** restricting broker access
- [ ] **PVCs** with `Retain` reclaim policy
- [ ] **Pod disruption budgets** (min 2 brokers available)
- [ ] **Liveness/readiness probes** tuned for your hardware
- [ ] **Prometheus + Grafana** with Confluent JMX dashboards
- [ ] **Alerting** on under-replicated partitions, ISR shrink
- [ ] **NiFi cluster** (3+ nodes) with shared ZooKeeper
- [ ] **Backup** of NiFi flows to NiFi Registry (Git backend)
- [ ] **CI/CD** for manifest changes (GitOps with ArgoCD/Flux)
- [ ] **Load balancer** / Ingress for external access
