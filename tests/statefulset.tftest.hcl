mock_provider "kubernetes" {}

run "statefulset_sparse" {
  command = plan

  variables {
    namespace     = "default"
    name          = "statefulset-sparse"
    image         = "nginx:latest"
    workload_type = "StatefulSet"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.this[0].metadata[0].name == "statefulset-sparse"
    error_message = "statefulset name should be set"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.this[0].spec[0].service_name == "statefulset-sparse-headless"
    error_message = "statefulset should reference headless service"
  }

  assert {
    condition     = kubernetes_service_v1.this[0].metadata[0].name == "statefulset-sparse"
    error_message = "service should be created"
  }

  assert {
    condition     = kubernetes_service_v1.headless[0].metadata[0].name == "statefulset-sparse-headless"
    error_message = "headless service should be created automatically"
  }

  assert {
    condition     = kubernetes_service_v1.headless[0].spec[0].cluster_ip == "None"
    error_message = "headless service should have clusterIP None"
  }

  assert {
    condition     = length(kubernetes_deployment_v1.this) == 0
    error_message = "deployment should not be created for StatefulSet type"
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.this) == 0
    error_message = "cronjob should not be created for StatefulSet type"
  }

  assert {
    condition     = length(nonsensitive(kubernetes_secret_v1.env.data)) == 0
    error_message = "secret should have no data when env_vars is empty"
  }

  assert {
    condition     = kubernetes_secret_v1.env.metadata[0].name == "statefulset-sparse-env-44136fa3"
    error_message = "secret name should include content hash suffix"
  }
}

run "statefulset_full" {
  command = plan

  variables {
    namespace     = "default"
    name          = "statefulset-full"
    image         = "postgres:16"
    workload_type = "StatefulSet"
    replicas      = 3

    env_vars = {
      "PGDATA" = "/var/lib/postgresql/data"
    }

    resources = {
      requests = {
        cpu    = "250m"
        memory = "512Mi"
      }
      limits = {
        cpu    = "1"
        memory = "1Gi"
      }
    }

    container_port = 5432
    service_port   = 5432

    liveness_probe = {
      httpGet = {
        path = "/health"
        port = 5432
      }
    }

    readiness_probe = {
      httpGet = {
        path = "/ready"
        port = 5432
      }
    }

    service_account_name = "my-sa"

    extra_containers = [
      {
        name  = "metrics-exporter"
        image = "prometheuscommunity/postgres-exporter:latest"
        port  = 9187
        env = {
          DATA_SOURCE_NAME = "postgresql://localhost:5432/postgres?sslmode=disable"
        }
      }
    ]
  }

  assert {
    condition     = kubernetes_stateful_set_v1.this[0].metadata[0].name == "statefulset-full"
    error_message = "statefulset name should be set"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.this[0].spec[0].replicas == "3"
    error_message = "replicas should be 3"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.this[0].spec[0].template[0].spec[0].service_account_name == "my-sa"
    error_message = "service account should be set"
  }

  assert {
    condition     = nonsensitive(kubernetes_secret_v1.env.data["PGDATA"]) == "/var/lib/postgresql/data"
    error_message = "secret should contain PGDATA"
  }

  assert {
    condition     = kubernetes_secret_v1.env.metadata[0].name == "statefulset-full-env-04abaf17"
    error_message = "secret name should include content hash suffix"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.this[0].spec[0].template[0].spec[0].container[0].env_from[0].secret_ref[0].name == kubernetes_secret_v1.env.metadata[0].name
    error_message = "statefulset should reference env secret"
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.this[0].spec[0].template[0].spec[0].container) == 2
    error_message = "should have 2 containers (1 primary + 1 sidecar)"
  }

  assert {
    condition     = kubernetes_stateful_set_v1.this[0].spec[0].template[0].spec[0].container[1].name == "metrics-exporter"
    error_message = "extra container name should be metrics-exporter"
  }
}
