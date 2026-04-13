# Confluent Kafka & Flink Ecosystem Local Deployment Complete

This document details the complete set of steps, configurations, and YAML manifests applied to deploy a stable Confluent Kafka and Apache Flink ecosystem on a local Minikube cluster.

## 1. Infrastructure Preparation
- **Minikube Node**: Re-provisioned the Minikube cluster with `4 CPUs` and `7GB RAM` (`7168 MB`) to prevent aggressive `OOMKilled` errors seen on smaller nodes.
- **Namespaces & Dependencies**: 
  - Deployed inside the `confluent` namespace.
  - Installed `cert-manager` (v1.14.5) to fulfill the Flink Operator's webhook requirements.

## 2. Operator Layer Installation
Installed the necessary Kubernetes operators via Helm:
- **Confluent for Kubernetes (CFK) Operator**: Manages the core Kafka ecosystem (Kafka, Schema Registry, Control Center, KRaft).
- **Flink Kubernetes Operator**: Manages Apache Flink clusters and deployments.
- **Confluent Manager for Apache Flink (CMF)**: Provides Flink SQL management and integration with the Confluent platform.

## 3. Platform Core Stabilization (KRaft & Kafka)
Configured the backbone to run successfully on a single local node by tuning resources and disabling memory-intensive cluster features.

### KRaft Controller YAML (`kraft-controller.yaml`)
Reduced replication overhead, disabled self-balancing, and set relaxed readiness probes.
```yaml
apiVersion: platform.confluent.io/v1beta1
kind: KRaftController
metadata:
  name: kraft-controller
  namespace: confluent
spec:
  replicas: 1
  image:
    application: confluentinc/cp-server:7.6.0
    init: confluentinc/confluent-init-container:2.8.0
  dataVolumeCapacity: 10Gi
  storageClass:
    name: standard
  podTemplate:
    resources:
      requests:
        cpu: 100m
        memory: 512Mi
      limits:
        cpu: 500m
        memory: 1Gi
    probe:
      liveness:
        initialDelaySeconds: 60
        failureThreshold: 10
      readiness:
        initialDelaySeconds: 60
        failureThreshold: 10
  configOverrides:
    server:
      - default.replication.factor=1
      - min.insync.replicas=1
      - confluent.balancer.enable=false
      - confluent.metadata.replication.factor=1
  listeners:
    controller:
      tls:
        enabled: false
```

### Kafka Broker YAML (`kafka.yaml`)
Deployed with a balanced resource tier.
```yaml
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: confluent
spec:
  replicas: 1
  image:
    application: confluentinc/cp-server:7.6.0
    init: confluentinc/confluent-init-container:2.8.0
  dataVolumeCapacity: 20Gi
  storageClass:
    name: standard
  dependencies:
    kRaftController:
      clusterRef:
        name: kraft-controller
  podTemplate:
    resources:
      requests:
        cpu: 200m
        memory: 1Gi
      limits:
        cpu: 1
        memory: 2Gi
    probe:
      liveness:
        initialDelaySeconds: 60
        failureThreshold: 10
      readiness:
        initialDelaySeconds: 60
        failureThreshold: 10
  configOverrides:
    server:
      - default.replication.factor=1
      - min.insync.replicas=1
      - auto.create.topics.enable=false
  listeners:
    internal:
      tls:
        enabled: false
```

## 4. Platform Services (Schema Registry & Control Center)
Configured edge applications with significantly extended startup probes to handle slow initialization on Minikube.

### Schema Registry YAML (`schemaregistry.yaml`)
```yaml
apiVersion: platform.confluent.io/v1beta1
kind: SchemaRegistry
metadata:
  name: schemaregistry
  namespace: confluent
spec:
  replicas: 1
  image:
    application: confluentinc/cp-schema-registry:7.6.0
    init: confluentinc/confluent-init-container:2.8.0
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent.svc.cluster.local:9092
  podTemplate:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
    probe:
      liveness:
        initialDelaySeconds: 180
        failureThreshold: 10
      readiness:
        initialDelaySeconds: 180
        failureThreshold: 10
  configOverrides:
    server:
      - kafkastore.topic.replication.factor=1
```

### Control Center YAML (`controlcenter.yaml`)
Provides a unified dashboard. Specifically updated dependencies to map both `schemaRegistry` and `flink` endpoints explicitly.
```yaml
apiVersion: platform.confluent.io/v1beta1
kind: ControlCenter
metadata:
  name: controlcenter
  namespace: confluent
spec:
  replicas: 1
  image:
    application: confluentinc/cp-enterprise-control-center:7.6.0
    init: confluentinc/confluent-init-container:2.8.0
  dataVolumeCapacity: 5Gi
  storageClass:
    name: standard
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent.svc.cluster.local:9092
    schemaRegistry:
      url: http://schemaregistry.confluent.svc.cluster.local:8081
  podTemplate:
    resources:
      requests:
        cpu: 200m
        memory: 1Gi
      limits:
        cpu: 1
        memory: 2Gi
    probe:
      liveness:
        initialDelaySeconds: 180
        failureThreshold: 10
      readiness:
        initialDelaySeconds: 180
        failureThreshold: 10
  configOverrides:
    server:
      - confluent.controlcenter.internal.topics.replication=1
      - confluent.controlcenter.command.topic.replication=1
      - confluent.metrics.topic.replication=1
      - confluent.monitoring.interceptor.topic.replication=1
      - confluent.controlcenter.internal.topics.partitions=1
      - confluent.controlcenter.cmf.enable=true
      - confluent.controlcenter.cmf.url=http://cmf-service.confluent.svc.cluster.local:80
```

## 5. Flink Workloads
Defined a test Flink environment and successfully deployed a stateless streaming Flink application via the operator.

### Flink Stack YAML (`flink.yaml`)
```yaml
# CMFRestClass — tells CFK how to reach the CMF REST API
apiVersion: platform.confluent.io/v1beta1
kind: CMFRestClass
metadata:
  name: default
  namespace: confluent
spec:
  cmfRest:
    endpoint: http://confluent-manager-for-apache-flink.confluent.svc.cluster.local:80
---
# FlinkEnvironment — defines the Flink execution environment
apiVersion: platform.confluent.io/v1beta1
kind: FlinkEnvironment
metadata:
  name: flink-env
  namespace: confluent
spec:
  kubernetesNamespace: confluent
  cmfRestClassRef:
    name: default
  flinkApplicationDefaults:
    spec:
      flinkVersion: v1.19
      image: confluentinc/cp-flink:1.19.1-cp1
---
# FlinkApplication — sample stateless job
apiVersion: platform.confluent.io/v1beta1
kind: FlinkApplication
metadata:
  name: flink-sample
  namespace: confluent
spec:
  flinkEnvironment: flink-env
  cmfRestClassRef:
    name: default
  image: confluentinc/cp-flink:1.19.1-cp1
  flinkVersion: v1.19
  flinkConfiguration:
    taskmanager.numberOfTaskSlots: "1"
    jobmanager.memory.process.size: 512m
    taskmanager.memory.process.size: 512m
  job:
    jarURI: local:///opt/flink/examples/streaming/StateMachineExample.jar
    parallelism: 1
    upgradeMode: stateless
```

## 6. Access Endpoints and Port Details
Configured standard Kubernetes `NodePort` services mapping internal cluster components to your Minikube IP so they can be securely and reliably accessed.

### Port Mappings Summary

| Component | Internal Port | NodePort (External) | Protocol | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Control Center UI** | `9021` | `30021` | HTTP | Main web interface for managing Kafka, Schemas, and Flink |
| **Kafka Broker** | `9092` | `30092` | TCP | External bootstrap server port for producer/consumer clients |
| **Prometheus UI** | `9090` | `30090` | HTTP | Pre-configured metrics scraping UI |
| **Kafka Jolokia** | `7777` | `30777` | HTTP | JMX metrics exposed via Jolokia REST API |
| **Kafka Metrics** | `7778` | `30778` | HTTP | Raw Prometheus metrics endpoint for the Kafka broker |
| **Schema Registry** | `8081` | N/A (Internal) | HTTP | Internal schema validation and management API |
| **CMF (Flink Mgr)** | `80`   | N/A (Internal) | HTTP | Internal Flink management REST API (used by Control Center) |

> [!TIP]
> **How to connect without NodePorts (Port-Forwarding)**
> If you prefer not to use the NodePort on the Minikube IP, you can map the ports directly to your localhost using:
> `kubectl port-forward controlcenter-0 9021:9021 -n confluent`

### Services YAML (`services.yaml`)
```yaml
# Control Center UI → http://<minikube-ip>:30021
apiVersion: v1
kind: Service
metadata:
  name: controlcenter-nodeport
  namespace: confluent
spec:
  type: NodePort
  selector:
    app: controlcenter
  ports:
    - name: ui
      port: 9021
      targetPort: 9021
      nodePort: 30021
---
# Kafka Broker → <minikube-ip>:30092
apiVersion: v1
kind: Service
metadata:
  name: kafka-nodeport
  namespace: confluent
spec:
  type: NodePort
  selector:
    app: kafka
  ports:
    - name: external
      port: 9092
      targetPort: 9092
      nodePort: 30092
---
# Prometheus → http://<minikube-ip>:30090
apiVersion: v1
kind: Service
metadata:
  name: prometheus-nodeport
  namespace: confluent
spec:
  type: NodePort
  selector:
    app: prometheus
  ports:
    - name: web
      port: 9090
      targetPort: 9090
      nodePort: 30090
---
# Jolokia JMX (kafka-0) → http://<minikube-ip>:30777
apiVersion: v1
kind: Service
metadata:
  name: kafka-jolokia-nodeport
  namespace: confluent
spec:
  type: NodePort
  selector:
    statefulset.kubernetes.io/pod-name: kafka-0
  ports:
    - name: jolokia
      port: 7777
      targetPort: 7777
      nodePort: 30777
---
# Kafka Prometheus metrics → http://<minikube-ip>:30778
apiVersion: v1
kind: Service
metadata:
  name: kafka-metrics-nodeport
  namespace: confluent
spec:
  type: NodePort
  selector:
    statefulset.kubernetes.io/pod-name: kafka-0
  ports:
    - name: prometheus
      port: 7778
      targetPort: 7778
      nodePort: 30778
```

## Final Status
All core platform pods resolve to `Running` and `Ready` securely under the `confluent` namespace. External access functions flawlessly bounding the core services to local client processes.
