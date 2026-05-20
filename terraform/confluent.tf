# =============================================================
#  Confluent Platform – Terraform (Docker provider)
#  Mirrors: docker-compose.yml (Kafka KRaft, Schema Registry,
#           Control Center, Prometheus)
# =============================================================

# ── Shared network ──────────────────────────────────────────
resource "docker_network" "confluent" {
  name   = "confluent"
  driver = "bridge"
}

# ── Volumes ─────────────────────────────────────────────────
resource "docker_volume" "kafka_data" {
  name = "kafka-data"
}

resource "docker_volume" "controlcenter_data" {
  name = "controlcenter-data"
}

resource "docker_volume" "prometheus_data" {
  name = "prometheus-data"
}

# ── Images ──────────────────────────────────────────────────
resource "docker_image" "kafka" {
  name         = var.kafka_image
  keep_locally = true
}

resource "docker_image" "schema_registry" {
  name         = var.schema_registry_image
  keep_locally = true
}

resource "docker_image" "control_center" {
  name         = var.control_center_image
  keep_locally = true
}

resource "docker_image" "prometheus" {
  name         = var.prometheus_image
  keep_locally = true
}

# ── Kafka (KRaft combined broker + controller) ───────────────
# Mirrors: kraft-controller.yaml + kafka.yaml
resource "docker_container" "kafka" {
  name     = "kafka"
  image    = docker_image.kafka.image_id
  hostname = "kafka"
  restart  = "unless-stopped"

  networks_advanced {
    name = docker_network.confluent.name
  }

  ports {
    internal = 9092
    external = 9092
  }
  ports {
    internal = 9101
    external = 9101
  }

  volumes {
    volume_name    = docker_volume.kafka_data.name
    container_path = "/var/lib/kafka/data"
  }

  # Resource limits (mirrors podTemplate.resources)
  memory      = 2048  # MB  → limits.memory: 2Gi
  memory_swap = 2048  # disable swap
  cpu_shares  = 1024  # relative weight (limits.cpu: 1)

  env = [
    # KRaft identity
    "KAFKA_NODE_ID=1",
    "KAFKA_PROCESS_ROLES=broker,controller",
    "KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:29093",

    # Listeners
    "KAFKA_LISTENERS=PLAINTEXT://kafka:29092,CONTROLLER://kafka:29093,EXTERNAL://0.0.0.0:9092",
    "KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:29092,EXTERNAL://localhost:9092",
    "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT,EXTERNAL:PLAINTEXT",
    "KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT",
    "KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER",

    # Replication / topic config (mirrors configOverrides)
    "KAFKA_DEFAULT_REPLICATION_FACTOR=1",
    "KAFKA_MIN_INSYNC_REPLICAS=1",
    "KAFKA_AUTO_CREATE_TOPICS_ENABLE=false",
    "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1",
    "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1",
    "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1",
    "KAFKA_CONFLUENT_BALANCER_ENABLE=false",
    "KAFKA_CONFLUENT_METADATA_TOPIC_REPLICATION_FACTOR=1",

    # Cluster ID (KRaft requirement)
    "CLUSTER_ID=${var.kafka_cluster_id}",

    # JMX
    "KAFKA_JMX_PORT=9101",
    "KAFKA_JMX_HOSTNAME=localhost",

    # Metrics reporter
    "KAFKA_METRIC_REPORTERS=io.confluent.metrics.reporter.ConfluentMetricsReporter",
    "CONFLUENT_METRICS_REPORTER_BOOTSTRAP_SERVERS=kafka:29092",
    "CONFLUENT_METRICS_REPORTER_TOPIC_REPLICAS=1",
    "CONFLUENT_METRICS_ENABLE=true",
    "CONFLUENT_SUPPORT_CUSTOMER_ID=anonymous",

    "KAFKA_LOG4J_ROOT_LOGLEVEL=WARN",
  ]

  healthcheck {
    test         = ["CMD", "kafka-broker-api-versions", "--bootstrap-server", "localhost:9092"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 10
    start_period = "60s"
  }
}

# ── Schema Registry ──────────────────────────────────────────
# Mirrors: schemaregistry.yaml
resource "docker_container" "schema_registry" {
  name     = "schema-registry"
  image    = docker_image.schema_registry.image_id
  hostname = "schema-registry"
  restart  = "unless-stopped"

  depends_on = [docker_container.kafka]

  networks_advanced {
    name = docker_network.confluent.name
  }

  ports {
    internal = 8081
    external = 8081
  }

  memory     = 512   # MB  → limits.memory: 512Mi
  cpu_shares = 512   # limits.cpu: 0.5

  env = [
    "SCHEMA_REGISTRY_HOST_NAME=schema-registry",
    "SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS=kafka:29092",
    "SCHEMA_REGISTRY_LISTENERS=http://0.0.0.0:8081",
    "SCHEMA_REGISTRY_KAFKASTORE_TOPIC_REPLICATION_FACTOR=1",  # mirrors kafkastore.topic.replication.factor=1
    "SCHEMA_REGISTRY_LOG4J_ROOT_LOGLEVEL=WARN",
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8081/subjects"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 10
    start_period = "180s"
  }
}

# ── Control Center ───────────────────────────────────────────
# Mirrors: controlcenter.yaml
resource "docker_container" "control_center" {
  name     = "control-center"
  image    = docker_image.control_center.image_id
  hostname = "control-center"
  restart  = "unless-stopped"

  depends_on = [
    docker_container.kafka,
    docker_container.schema_registry,
  ]

  networks_advanced {
    name = docker_network.confluent.name
  }

  ports {
    internal = 9021
    external = 9021
  }

  volumes {
    volume_name    = docker_volume.controlcenter_data.name
    container_path = "/var/lib/confluent-control-center"
  }

  memory     = 2048
  cpu_shares = 1024

  env = [
    "CONTROL_CENTER_BOOTSTRAP_SERVERS=kafka:29092",
    "CONTROL_CENTER_SCHEMA_REGISTRY_URL=http://schema-registry:8081",

    # Internal topic replication (mirrors configOverrides)
    "CONTROL_CENTER_REPLICATION_FACTOR=1",
    "CONTROL_CENTER_INTERNAL_TOPICS_REPLICATION=1",
    "CONTROL_CENTER_COMMAND_TOPIC_REPLICATION=1",
    "CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_REPLICATION=1",
    "CONFLUENT_METRICS_TOPIC_REPLICATION=1",
    "CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS=1",

    "PORT=9021",
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:9021/healthcheck"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 10
    start_period = "180s"
  }
}

# ── Prometheus ───────────────────────────────────────────────
# Mirrors: prometheus.yaml (ConfigMap + Deployment + Service)
resource "docker_container" "prometheus" {
  name     = "prometheus"
  image    = docker_image.prometheus.image_id
  hostname = "prometheus"
  restart  = "unless-stopped"

  networks_advanced {
    name = docker_network.confluent.name
  }

  ports {
    internal = 9090
    external = 9090
  }

  # Mount the local prometheus.yml (equivalent of ConfigMap volume mount)
  volumes {
    host_path      = abspath("${path.module}/../confluent-docker/prometheus/prometheus.yml")
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.prometheus_data.name
    container_path = "/prometheus"
  }

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.retention.time=24h",
  ]

  memory     = 512
  cpu_shares = 512

  healthcheck {
    test         = ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }
}
