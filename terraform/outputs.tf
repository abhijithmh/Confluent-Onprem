# ── Confluent Stack ─────────────────────────────────────────────────────
output "kafka_endpoint" {
  description = "Kafka external bootstrap server"
  value       = "localhost:9092"
}

output "schema_registry_url" {
  description = "Schema Registry REST endpoint"
  value       = "http://localhost:8081"
}

output "control_center_url" {
  description = "Confluent Control Center UI"
  value       = "http://localhost:9021"
}

output "prometheus_url" {
  description = "Prometheus UI"
  value       = "http://localhost:9090"
}

# ── NiFi Stack ──────────────────────────────────────────────────────────
output "nifi_ui_url" {
  description = "Apache NiFi UI (HTTPS, self-signed cert)"
  value       = "https://localhost:8443/nifi"
}

output "nifi_username" {
  description = "NiFi login username"
  value       = var.nifi_username
}

output "nifi_password" {
  description = "NiFi login password"
  value       = var.nifi_password
  sensitive   = true
}

output "nifi_registry_url" {
  description = "NiFi Registry UI"
  value       = "http://localhost:18080/nifi-registry"
}

output "kafka_internal_endpoint" {
  description = "Kafka bootstrap for NiFi processors (when connect_nifi_to_kafka=true)"
  value       = "kafka:29092"
}
