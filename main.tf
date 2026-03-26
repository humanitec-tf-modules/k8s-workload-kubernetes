# =============================================================================
# Universal K8s Workload Module — Main
# =============================================================================

locals {
  common_labels = merge(
    {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/managed-by" = "humanitec"
    },
    var.labels,
  )

  # Pod template — shared between Deployment, StatefulSet & CronJob
  pod_labels = local.common_labels

  is_deployment  = var.workload_type == "Deployment"
  is_statefulset = var.workload_type == "StatefulSet"
  is_cronjob     = var.workload_type == "CronJob"
  has_service    = local.is_deployment || local.is_statefulset
}

# ---------------------------------------------------------------------------
# Secret (stores all env vars)
# ---------------------------------------------------------------------------

resource "kubernetes_secret_v1" "env" {
  metadata {
    name      = "${var.name}-env"
    namespace = var.namespace
    labels    = local.common_labels
  }

  data = var.env_vars
}

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

resource "kubernetes_deployment_v1" "this" {
  count = local.is_deployment ? 1 : 0

  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.annotations
  }

  wait_for_rollout = var.wait_for_rollout

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = var.name
      }
    }

    template {
      metadata {
        labels      = local.pod_labels
        annotations = var.annotations
      }

      spec {
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secrets
          content {
            name = image_pull_secrets.value
          }
        }

        service_account_name = var.service_account_name != "" ? var.service_account_name : null
        node_selector        = length(var.node_selector) > 0 ? var.node_selector : null

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        container {
          name    = var.name
          image   = var.image
          command = length(var.command) > 0 ? var.command : null
          args    = length(var.args) > 0 ? var.args : null

          port {
            container_port = var.container_port
            protocol       = "TCP"
          }

          # --- Env vars from Secret ---
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.env.metadata[0].name
            }
          }

          # --- Resources ---
          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          # --- Probes ---
          dynamic "liveness_probe" {
            for_each = var.liveness_probe != null ? [var.liveness_probe] : []
            content {
              http_get {
                path = liveness_probe.value.httpGet.path
                port = liveness_probe.value.httpGet.port
              }
              initial_delay_seconds = liveness_probe.value.initialDelaySeconds
              period_seconds        = liveness_probe.value.periodSeconds
              failure_threshold     = liveness_probe.value.failureThreshold
            }
          }

          dynamic "readiness_probe" {
            for_each = var.readiness_probe != null ? [var.readiness_probe] : []
            content {
              http_get {
                path = readiness_probe.value.httpGet.path
                port = readiness_probe.value.httpGet.port
              }
              initial_delay_seconds = readiness_probe.value.initialDelaySeconds
              period_seconds        = readiness_probe.value.periodSeconds
              failure_threshold     = readiness_probe.value.failureThreshold
            }
          }

          # --- Volume mounts ---
          dynamic "volume_mount" {
            for_each = var.volumes
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
              read_only  = volume_mount.value.read_only
            }
          }
        }

        # --- Extra containers (sidecars) ---
        dynamic "container" {
          for_each = var.extra_containers
          content {
            name    = container.value.name
            image   = container.value.image
            command = length(container.value.command) > 0 ? container.value.command : null
            args    = length(container.value.args) > 0 ? container.value.args : null

            dynamic "port" {
              for_each = container.value.port != null ? [container.value.port] : []
              content {
                container_port = port.value
                protocol       = "TCP"
              }
            }

            dynamic "env" {
              for_each = container.value.env
              content {
                name  = env.key
                value = env.value
              }
            }

            resources {
              requests = {
                cpu    = container.value.resources.requests.cpu
                memory = container.value.resources.requests.memory
              }
              limits = {
                cpu    = container.value.resources.limits.cpu
                memory = container.value.resources.limits.memory
              }
            }

            dynamic "volume_mount" {
              for_each = container.value.volume_mounts
              content {
                name       = volume_mount.value.name
                mount_path = volume_mount.value.mount_path
                read_only  = volume_mount.value.read_only
              }
            }

            dynamic "security_context" {
              for_each = container.value.security_context != null ? [container.value.security_context] : []
              content {
                run_as_user                = security_context.value.run_as_user
                run_as_group               = security_context.value.run_as_group
                run_as_non_root            = security_context.value.run_as_non_root
                read_only_root_filesystem  = security_context.value.read_only_root_filesystem
                privileged                 = security_context.value.privileged
                allow_privilege_escalation = security_context.value.allow_privilege_escalation
              }
            }
          }
        }

        # --- Volumes ---
        dynamic "volume" {
          for_each = [for v in var.volumes : v if v.type == "emptyDir"]
          content {
            name = volume.value.name
            empty_dir {}
          }
        }

        dynamic "volume" {
          for_each = [for v in var.volumes : v if v.type == "configMap"]
          content {
            name = volume.value.name
            config_map {
              name = volume.value.source
            }
          }
        }

        dynamic "volume" {
          for_each = [for v in var.volumes : v if v.type == "pvc"]
          content {
            name = volume.value.name
            persistent_volume_claim {
              claim_name = volume.value.source
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Let HPA / external controllers manage replicas
      spec[0].replicas,
    ]
  }
}

# ---------------------------------------------------------------------------
# StatefulSet
# ---------------------------------------------------------------------------

resource "kubernetes_stateful_set_v1" "this" {
  count = local.is_statefulset ? 1 : 0

  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.annotations
  }

  wait_for_rollout = var.wait_for_rollout

  spec {
    replicas     = var.replicas
    service_name = "${var.name}-headless"

    selector {
      match_labels = {
        "app.kubernetes.io/name" = var.name
      }
    }

    template {
      metadata {
        labels      = local.pod_labels
        annotations = var.annotations
      }

      spec {
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secrets
          content {
            name = image_pull_secrets.value
          }
        }

        service_account_name = var.service_account_name != "" ? var.service_account_name : null
        node_selector        = length(var.node_selector) > 0 ? var.node_selector : null

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        container {
          name    = var.name
          image   = var.image
          command = length(var.command) > 0 ? var.command : null
          args    = length(var.args) > 0 ? var.args : null

          port {
            container_port = var.container_port
            protocol       = "TCP"
          }

          # --- Env vars from Secret ---
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.env.metadata[0].name
            }
          }

          # --- Resources ---
          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          # --- Probes ---
          dynamic "liveness_probe" {
            for_each = var.liveness_probe != null ? [var.liveness_probe] : []
            content {
              http_get {
                path = liveness_probe.value.httpGet.path
                port = liveness_probe.value.httpGet.port
              }
              initial_delay_seconds = liveness_probe.value.initialDelaySeconds
              period_seconds        = liveness_probe.value.periodSeconds
              failure_threshold     = liveness_probe.value.failureThreshold
            }
          }

          dynamic "readiness_probe" {
            for_each = var.readiness_probe != null ? [var.readiness_probe] : []
            content {
              http_get {
                path = readiness_probe.value.httpGet.path
                port = readiness_probe.value.httpGet.port
              }
              initial_delay_seconds = readiness_probe.value.initialDelaySeconds
              period_seconds        = readiness_probe.value.periodSeconds
              failure_threshold     = readiness_probe.value.failureThreshold
            }
          }

          # --- Volume mounts ---
          dynamic "volume_mount" {
            for_each = var.volumes
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
              read_only  = volume_mount.value.read_only
            }
          }
        }

        # --- Extra containers (sidecars) ---
        dynamic "container" {
          for_each = var.extra_containers
          content {
            name    = container.value.name
            image   = container.value.image
            command = length(container.value.command) > 0 ? container.value.command : null
            args    = length(container.value.args) > 0 ? container.value.args : null

            dynamic "port" {
              for_each = container.value.port != null ? [container.value.port] : []
              content {
                container_port = port.value
                protocol       = "TCP"
              }
            }

            dynamic "env" {
              for_each = container.value.env
              content {
                name  = env.key
                value = env.value
              }
            }

            resources {
              requests = {
                cpu    = container.value.resources.requests.cpu
                memory = container.value.resources.requests.memory
              }
              limits = {
                cpu    = container.value.resources.limits.cpu
                memory = container.value.resources.limits.memory
              }
            }

            dynamic "volume_mount" {
              for_each = container.value.volume_mounts
              content {
                name       = volume_mount.value.name
                mount_path = volume_mount.value.mount_path
                read_only  = volume_mount.value.read_only
              }
            }

            dynamic "security_context" {
              for_each = container.value.security_context != null ? [container.value.security_context] : []
              content {
                run_as_user                = security_context.value.run_as_user
                run_as_group               = security_context.value.run_as_group
                run_as_non_root            = security_context.value.run_as_non_root
                read_only_root_filesystem  = security_context.value.read_only_root_filesystem
                privileged                 = security_context.value.privileged
                allow_privilege_escalation = security_context.value.allow_privilege_escalation
              }
            }
          }
        }

        # --- Volumes ---
        dynamic "volume" {
          for_each = [for v in var.volumes : v if v.type == "emptyDir"]
          content {
            name = volume.value.name
            empty_dir {}
          }
        }

        dynamic "volume" {
          for_each = [for v in var.volumes : v if v.type == "configMap"]
          content {
            name = volume.value.name
            config_map {
              name = volume.value.source
            }
          }
        }

        dynamic "volume" {
          for_each = [for v in var.volumes : v if v.type == "pvc"]
          content {
            name = volume.value.name
            persistent_volume_claim {
              claim_name = volume.value.source
            }
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# CronJob
# ---------------------------------------------------------------------------

resource "kubernetes_cron_job_v1" "this" {
  count = local.is_cronjob ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.cron_schedule != ""
      error_message = "cron_schedule must be set when workload_type is 'CronJob'."
    }
  }

  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.annotations
  }

  spec {
    schedule                      = var.cron_schedule
    concurrency_policy            = var.cron_concurrency_policy
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = local.pod_labels
      }

      spec {
        template {
          metadata {
            labels = local.pod_labels
          }

          spec {
            restart_policy       = "OnFailure"
            service_account_name = var.service_account_name != "" ? var.service_account_name : null
            node_selector        = length(var.node_selector) > 0 ? var.node_selector : null

            dynamic "image_pull_secrets" {
              for_each = var.image_pull_secrets
              content {
                name = image_pull_secrets.value
              }
            }

            dynamic "toleration" {
              for_each = var.tolerations
              content {
                key      = toleration.value.key
                operator = toleration.value.operator
                value    = toleration.value.value
                effect   = toleration.value.effect
              }
            }

            container {
              name    = var.name
              image   = var.image
              command = length(var.command) > 0 ? var.command : null
              args    = length(var.args) > 0 ? var.args : null

              env_from {
                secret_ref {
                  name = kubernetes_secret_v1.env.metadata[0].name
                }
              }

              resources {
                requests = {
                  cpu    = var.resources.requests.cpu
                  memory = var.resources.requests.memory
                }
                limits = {
                  cpu    = var.resources.limits.cpu
                  memory = var.resources.limits.memory
                }
              }

              # --- Volume mounts ---
              dynamic "volume_mount" {
                for_each = var.volumes
                content {
                  name       = volume_mount.value.name
                  mount_path = volume_mount.value.mount_path
                  read_only  = volume_mount.value.read_only
                }
              }
            }

            # --- Extra containers (sidecars) ---
            dynamic "container" {
              for_each = var.extra_containers
              content {
                name    = container.value.name
                image   = container.value.image
                command = length(container.value.command) > 0 ? container.value.command : null
                args    = length(container.value.args) > 0 ? container.value.args : null

                dynamic "env" {
                  for_each = container.value.env
                  content {
                    name  = env.key
                    value = env.value
                  }
                }

                resources {
                  requests = {
                    cpu    = container.value.resources.requests.cpu
                    memory = container.value.resources.requests.memory
                  }
                  limits = {
                    cpu    = container.value.resources.limits.cpu
                    memory = container.value.resources.limits.memory
                  }
                }

                dynamic "volume_mount" {
                  for_each = container.value.volume_mounts
                  content {
                    name       = volume_mount.value.name
                    mount_path = volume_mount.value.mount_path
                    read_only  = volume_mount.value.read_only
                  }
                }

                dynamic "security_context" {
                  for_each = container.value.security_context != null ? [container.value.security_context] : []
                  content {
                    run_as_user                = security_context.value.run_as_user
                    run_as_group               = security_context.value.run_as_group
                    run_as_non_root            = security_context.value.run_as_non_root
                    read_only_root_filesystem  = security_context.value.read_only_root_filesystem
                    privileged                 = security_context.value.privileged
                    allow_privilege_escalation = security_context.value.allow_privilege_escalation
                  }
                }
              }
            }

            # --- Volumes ---
            dynamic "volume" {
              for_each = [for v in var.volumes : v if v.type == "emptyDir"]
              content {
                name = volume.value.name
                empty_dir {}
              }
            }

            dynamic "volume" {
              for_each = [for v in var.volumes : v if v.type == "configMap"]
              content {
                name = volume.value.name
                config_map {
                  name = volume.value.source
                }
              }
            }

            dynamic "volume" {
              for_each = [for v in var.volumes : v if v.type == "pvc"]
              content {
                name = volume.value.name
                persistent_volume_claim {
                  claim_name = volume.value.source
                }
              }
            }
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Service  (Deployments and StatefulSets)
# ---------------------------------------------------------------------------

resource "kubernetes_service_v1" "this" {
  count = local.has_service ? 1 : 0

  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.annotations
  }

  spec {
    type = var.service_type

    selector = {
      "app.kubernetes.io/name" = var.name
    }

    port {
      port        = var.service_port
      target_port = var.container_port
      protocol    = "TCP"
      name        = "http"
    }
  }
}

# ---------------------------------------------------------------------------
# Headless Service  (when enabled, or always for StatefulSets)
# ---------------------------------------------------------------------------

resource "kubernetes_service_v1" "headless" {
  count = (local.has_service && var.headless_service) || local.is_statefulset ? 1 : 0

  metadata {
    name        = "${var.name}-headless"
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.annotations
  }

  spec {
    type       = "ClusterIP"
    cluster_ip = "None"

    selector = {
      "app.kubernetes.io/name" = var.name
    }

    port {
      port        = var.service_port
      target_port = var.container_port
      protocol    = "TCP"
      name        = "http"
    }
  }
}
