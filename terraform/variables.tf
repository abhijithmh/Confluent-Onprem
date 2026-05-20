# ── Confluent stack tuning ──────────────────────────────────────────────
variable "kafka_image" {
  description = "Confluent Server image tag"
  type        = string
  default     = "confluentinc/cp-server:7.6.0"
}

variable "schema_registry_image" {
  description = "Schema Registry image tag"
  type        = string
  default     = "confluentinc/cp-schema-registry:7.6.0"
}

variable "control_center_image" {
  description = "Control Center image tag"
  type        = string
  default     = "confluentinc/cp-enterprise-control-center:7.6.0"
}

variable "prometheus_image" {
  description = "Prometheus image tag"
  type        = string
  default     = "prom/prometheus:latest"
}

variable "kafka_cluster_id" {
  description = "KRaft cluster ID (must be stable across recreates)"
  type        = string
  default     = "MkU3OEVBNTcwNTJENDM2Qk"
}

variable "kafka_heap_mb" {
  description = "Kafka JVM heap (MB)"
  type        = number
  default     = 1024
}

# ── NiFi stack tuning ───────────────────────────────────────────────────
variable "nifi_image" {
  description = "Apache NiFi image tag"
  type        = string
  default     = "apache/nifi:2.2.0"
}

variable "nifi_registry_image" {
  description = "NiFi Registry image tag"
  type        = string
  default     = "apache/nifi-registry:latest"
}

variable "nifi_username" {
  description = "NiFi single-user login username"
  type        = string
  default     = "admin"
}

variable "nifi_password" {
  description = "NiFi single-user login password (min 12 chars)"
  type        = string
  sensitive   = true
  default     = "NiFiAdmin@2024"
}

variable "connect_nifi_to_kafka" {
  description = "Attach NiFi to the Confluent network so it can reach kafka:29092"
  type        = bool
  default     = true
}
