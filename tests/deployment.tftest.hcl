mock_provider "kubernetes" {}

run "deployment_sparse" {
  command = plan

  variables {
    namespace = "default"
    name      = "deployment-sparse"
    image     = "nginx:latest"
  }

  assert {
    condition     = kubernetes_deployment_v1.this[0].metadata[0].name == "deployment-sparse"
    error_message = "deployment name should be set"
  }

  assert {
    condition     = kubernetes_service_v1.this[0].metadata[0].name == "deployment-sparse"
    error_message = "service name should be set"
  }

  assert {
    condition     = length(kubernetes_secret_v1.env) == 0
    error_message = "no secret should be created when env_vars is empty"
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.this) == 0
    error_message = "cronjob should not be created for Deployment type"
  }
}

run "deployment_full" {
  command = plan

  variables {
    namespace = "default"
    name      = "deployment-full"
    image     = "nginx:latest"

    env_vars = {
      "MY_ENV_VAR" = "my-value"
    }

    resources = {
      requests = {
        cpu    = "100m"
        memory = "128Mi"
      }
      limits = {
        cpu    = "200m"
        memory = "256Mi"
      }
    }

    container_port = 80
    service_port   = 80

    liveness_probe = {
      httpGet = {
        path = "/"
        port = 80
      }
    }

    readiness_probe = {
      httpGet = {
        path = "/"
        port = 80
      }
    }

    extra_containers = [
      {
        name  = "log-shipper"
        image = "fluent/fluent-bit:latest"
        port  = 2020
        env = {
          FLUSH_INTERVAL = "5"
        }
        security_context = {
          run_as_non_root           = true
          read_only_root_filesystem = true
          run_as_user               = 1000
        }
      }
    ]
  }

  assert {
    condition     = kubernetes_deployment_v1.this[0].metadata[0].name == "deployment-full"
    error_message = "deployment name should be set"
  }

  assert {
    condition     = kubernetes_service_v1.this[0].metadata[0].name == "deployment-full"
    error_message = "service name should be set"
  }

  assert {
    condition     = kubernetes_secret_v1.env[0].metadata[0].name == "deployment-full-env"
    error_message = "secret should be created for env vars"
  }

  assert {
    condition     = kubernetes_secret_v1.env[0].data["MY_ENV_VAR"] == "my-value"
    error_message = "secret should contain MY_ENV_VAR"
  }

  assert {
    condition     = kubernetes_deployment_v1.this[0].spec[0].template[0].spec[0].container[0].env_from[0].secret_ref[0].name == "deployment-full-env"
    error_message = "primary container should reference the env secret"
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.this) == 0
    error_message = "cronjob should not be created for Deployment type"
  }

  assert {
    condition     = length(kubernetes_deployment_v1.this[0].spec[0].template[0].spec[0].container) == 2
    error_message = "should have 2 containers (1 primary + 1 sidecar)"
  }

  assert {
    condition     = kubernetes_deployment_v1.this[0].spec[0].template[0].spec[0].container[1].name == "log-shipper"
    error_message = "extra container name should be log-shipper"
  }

  assert {
    condition     = kubernetes_deployment_v1.this[0].spec[0].template[0].spec[0].container[1].image == "fluent/fluent-bit:latest"
    error_message = "extra container should have correct image"
  }
}
