# =============================================================
#  Apache NiFi Stack – Terraform (Docker provider)
#  Mirrors: nifi/docker-compose.yml
#  Services: NiFi 2.x (HTTPS, single-user) + NiFi Registry
# =============================================================

# ── NiFi-specific network ────────────────────────────────────
resource "docker_network" "nifi" {
  name   = "nifi-net"
  driver = "bridge"
}

# ── NiFi Volumes ─────────────────────────────────────────────
resource "docker_volume" "nifi_conf" {
  name = "nifi-conf"
}

resource "docker_volume" "nifi_data" {
  name = "nifi-data"
}

resource "docker_volume" "nifi_logs" {
  name = "nifi-logs"
}

resource "docker_volume" "nifi_registry_database" {
  name = "nifi-registry-database"
}

resource "docker_volume" "nifi_registry_flow" {
  name = "nifi-registry-flow"
}

# ── NiFi Images ──────────────────────────────────────────────
resource "docker_image" "nifi" {
  name         = var.nifi_image
  keep_locally = true
}

resource "docker_image" "nifi_registry" {
  name         = var.nifi_registry_image
  keep_locally = true
}

# ── NiFi Registry ────────────────────────────────────────────
resource "docker_container" "nifi_registry" {
  name     = "nifi-registry"
  image    = docker_image.nifi_registry.image_id
  hostname = "nifi-registry"
  restart  = "unless-stopped"

  networks_advanced {
    name = docker_network.nifi.name
  }

  # If NiFi is also attached to Confluent network, Registry should follow
  dynamic "networks_advanced" {
    for_each = var.connect_nifi_to_kafka ? [1] : []
    content {
      name = docker_network.confluent.name
    }
  }

  ports {
    internal = 18080
    external = 18080
  }

  volumes {
    volume_name    = docker_volume.nifi_registry_database.name
    container_path = "/opt/nifi-registry/nifi-registry-current/database"
  }
  volumes {
    volume_name    = docker_volume.nifi_registry_flow.name
    container_path = "/opt/nifi-registry/nifi-registry-current/flow_storage"
  }

  memory     = 512
  cpu_shares = 512

  env = [
    "LOG_LEVEL=INFO",
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:18080/nifi-registry/actuator/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 10
    start_period = "60s"
  }
}

# ── Apache NiFi 2.x ──────────────────────────────────────────
resource "docker_container" "nifi" {
  name     = "nifi"
  image    = docker_image.nifi.image_id
  hostname = "nifi"
  restart  = "unless-stopped"

  depends_on = [docker_container.nifi_registry]

  networks_advanced {
    name = docker_network.nifi.name
  }

  # Optionally bridge into the Confluent network so NiFi processors
  # can reach kafka:29092 directly
  dynamic "networks_advanced" {
    for_each = var.connect_nifi_to_kafka ? [1] : []
    content {
      name = docker_network.confluent.name
    }
  }

  ports {
    internal = 8443
    external = 8443   # HTTPS UI → https://localhost:8443/nifi
  }

  volumes {
    volume_name    = docker_volume.nifi_conf.name
    container_path = "/opt/nifi/nifi-current/conf"
  }
  volumes {
    volume_name    = docker_volume.nifi_data.name
    container_path = "/opt/nifi/nifi-current/data"
  }
  volumes {
    volume_name    = docker_volume.nifi_logs.name
    container_path = "/opt/nifi/nifi-current/logs"
  }

  memory     = 2048
  cpu_shares = 1024

  env = [
    # Single-user auth (password >= 12 chars required by NiFi 2.x)
    "SINGLE_USER_CREDENTIALS_USERNAME=${var.nifi_username}",
    "SINGLE_USER_CREDENTIALS_PASSWORD=${var.nifi_password}",

    # HTTPS
    "NIFI_WEB_HTTPS_PORT=8443",
    "NIFI_WEB_HTTPS_HOST=0.0.0.0",
    # Required when accessing NiFi through Docker port mapping (prevents 403)
    "NIFI_WEB_PROXY_HOST=localhost:8443",

    # NiFi Registry connection
    "NIFI_REGISTRY_WEB_HTTP_HOST=nifi-registry",
    "NIFI_REGISTRY_WEB_HTTP_PORT=18080",

    # JVM
    "NIFI_JVM_HEAP_INIT=512m",
    "NIFI_JVM_HEAP_MAX=1g",

    # Single-node (no ZooKeeper/cluster needed)
    "NIFI_CLUSTER_IS_NODE=false",

    "NIFI_LOG_LEVEL=INFO",
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "-k", "https://localhost:8443/nifi-api/system-diagnostics"]
    interval     = "30s"
    timeout      = "15s"
    retries      = 10
    start_period = "90s"
  }
}
