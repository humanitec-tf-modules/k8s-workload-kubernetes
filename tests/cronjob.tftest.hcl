mock_provider "kubernetes" {}

run "cronjob_sparse" {
  command = plan

  variables {
    namespace     = "default"
    name          = "cleanup-job"
    image         = "busybox:latest"
    workload_type = "CronJob"
    cron_schedule = "0 2 * * *"
  }

  assert {
    condition     = kubernetes_cron_job_v1.this[0].metadata[0].name == "cleanup-job"
    error_message = "cronjob name should be set"
  }

  assert {
    condition     = kubernetes_cron_job_v1.this[0].spec[0].schedule == "0 2 * * *"
    error_message = "cronjob schedule should be set"
  }

  assert {
    condition     = length(kubernetes_deployment_v1.this) == 0
    error_message = "deployment should not be created for CronJob type"
  }

  assert {
    condition     = length(kubernetes_service_v1.this) == 0
    error_message = "service should not be created for CronJob type"
  }
}

run "cronjob_full" {
  command = plan

  variables {
    namespace               = "default"
    name                    = "etl-job"
    image                   = "python:3.12"
    workload_type           = "CronJob"
    cron_schedule           = "*/30 * * * *"
    cron_concurrency_policy = "Replace"
    args                    = ["python", "etl.py"]

    env_vars = {
      "DB_HOST" = "postgres.default.svc"
    }

    extra_containers = [
      {
        name  = "cloudsql-proxy"
        image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:latest"
        args  = ["--port=5432"]
        security_context = {
          run_as_non_root = true
        }
      }
    ]
  }

  assert {
    condition     = kubernetes_cron_job_v1.this[0].metadata[0].name == "etl-job"
    error_message = "cronjob name should be set"
  }

  assert {
    condition     = kubernetes_cron_job_v1.this[0].spec[0].concurrency_policy == "Replace"
    error_message = "concurrency policy should be Replace"
  }

  assert {
    condition     = kubernetes_secret_v1.env.metadata[0].name == "etl-job-env"
    error_message = "secret should be created for env vars"
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.this[0].spec[0].job_template[0].spec[0].template[0].spec[0].container) == 2
    error_message = "should have 2 containers (1 primary + 1 sidecar)"
  }

  assert {
    condition     = kubernetes_cron_job_v1.this[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[1].name == "cloudsql-proxy"
    error_message = "extra container name should be cloudsql-proxy"
  }
}
