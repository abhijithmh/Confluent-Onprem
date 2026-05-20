terraform {
  required_version = ">= 1.5"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Connect to local Docker daemon
provider "docker" {
  host = "unix:///var/run/docker.sock"
}
