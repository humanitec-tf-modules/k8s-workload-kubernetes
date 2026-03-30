# =============================================================================
# Universal K8s Workload Module — Variables
# =============================================================================

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "namespace" {
  description = "Kubernetes namespace to deploy into (injected by Humanitec)."
  type        = string
}

variable "name" {
  description = "Workload name — used for Deployment, Service, labels, selectors."
  type        = string
}

variable "labels" {
  description = "Additional labels to merge onto every resource."
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Additional annotations to merge onto every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Container
# ---------------------------------------------------------------------------

variable "image" {
  description = "Full container image reference."
  type        = string
}

variable "command" {
  description = "Override the container entrypoint."
  type        = list(string)
  default     = []
}

variable "args" {
  description = "Override the container args."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Workload shape
# ---------------------------------------------------------------------------

variable "workload_type" {
  description = "Kind of workload: 'Deployment', 'StatefulSet', or 'CronJob'."
  type        = string
  default     = "Deployment"

  validation {
    condition     = contains(["Deployment", "StatefulSet", "CronJob"], var.workload_type)
    error_message = "workload_type must be 'Deployment', 'StatefulSet', or 'CronJob'."
  }
}

variable "replicas" {
  description = "Desired replica count (ignored for CronJob)."
  type        = number
  default     = 1
}

variable "cron_schedule" {
  description = "Cron expression — only used when workload_type = CronJob."
  type        = string
  default     = ""
}

variable "cron_concurrency_policy" {
  description = "CronJob concurrencyPolicy (Allow | Forbid | Replace)."
  type        = string
  default     = "Forbid"

  validation {
    condition     = contains(["Allow", "Forbid", "Replace"], var.cron_concurrency_policy)
    error_message = "cron_concurrency_policy must be one of: Allow, Forbid, or Replace."
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "container_port" {
  description = "Primary port the container listens on."
  type        = number
  default     = 8080
}

variable "service_port" {
  description = "Port exposed by the Service."
  type        = number
  default     = 80
}

variable "service_type" {
  description = "Kubernetes Service type."
  type        = string
  default     = "ClusterIP"
}

variable "headless_service" {
  description = "Whether to create an additional headless (clusterIP: None) service."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Environment & config
# ---------------------------------------------------------------------------

variable "env_vars" {
  description = "Plain-text environment variables."
  type        = map(string)
  default     = {}
  sensitive   = true
}


# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

variable "resources" {
  description = <<-EOT
    Container resource requests and limits in Kubernetes-native shape:
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
  EOT
  type = object({
    requests = optional(object({
      cpu    = optional(string, "100m")
      memory = optional(string, "128Mi")
    }), {})
    limits = optional(object({
      cpu    = optional(string, "500m")
      memory = optional(string, "512Mi")
    }), {})
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Health checks
# ---------------------------------------------------------------------------

variable "liveness_probe" {
  description = <<-EOT
    Liveness probe in Kubernetes-native shape. Set to null to disable.
      liveness_probe:
        httpGet:
          path: /alive
          port: 8080
        initialDelaySeconds: 10
        periodSeconds: 10
        failureThreshold: 3
  EOT
  type = object({
    httpGet = object({
      path = string
      port = number
    })
    initialDelaySeconds = optional(number, 10)
    periodSeconds       = optional(number, 10)
    failureThreshold    = optional(number, 3)
  })
  default = null
}

variable "readiness_probe" {
  description = <<-EOT
    Readiness probe in Kubernetes-native shape. Set to null to disable.
      readiness_probe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 3
  EOT
  type = object({
    httpGet = object({
      path = string
      port = number
    })
    initialDelaySeconds = optional(number, 5)
    periodSeconds       = optional(number, 5)
    failureThreshold    = optional(number, 3)
  })
  default = null
}

# ---------------------------------------------------------------------------
# Volumes
# ---------------------------------------------------------------------------

variable "volumes" {
  description = <<-EOT
    Optional volumes to attach. Each entry creates a Volume + VolumeMount.
    Supports 'emptyDir', 'configMap', and 'pvc' types.
  EOT
  type = list(object({
    name       = string
    mount_path = string
    type       = string               # emptyDir | configMap | pvc
    source     = optional(string, "") # configMap name or PVC claim name
    read_only  = optional(bool, false)
  }))
  default = []

  validation {
    condition = alltrue([
      for v in var.volumes : contains(["emptyDir", "configMap", "pvc"], v.type)
    ])
    error_message = "volumes[*].type must be one of \"emptyDir\", \"configMap\", or \"pvc\"."
  }
}


# ---------------------------------------------------------------------------
# Extra containers (sidecars)
# ---------------------------------------------------------------------------

variable "extra_containers" {
  description = <<-EOT
    Additional sidecar containers to add to the pod spec.
    Each entry maps to a full container block in the Deployment/CronJob.
  EOT
  type = list(object({
    name    = string
    image   = string
    command = optional(list(string), [])
    args    = optional(list(string), [])
    port    = optional(number, null)
    env     = optional(map(string), {})
    resources = optional(object({
      requests = optional(object({
        cpu    = optional(string, "50m")
        memory = optional(string, "64Mi")
      }), {})
      limits = optional(object({
        cpu    = optional(string, "200m")
        memory = optional(string, "256Mi")
      }), {})
    }), {})
    volume_mounts = optional(list(object({
      name       = string
      mount_path = string
      read_only  = optional(bool, false)
    })), [])
    security_context = optional(object({
      run_as_user                = optional(number, null)
      run_as_group               = optional(number, null)
      run_as_non_root            = optional(bool, null)
      read_only_root_filesystem  = optional(bool, null)
      privileged                 = optional(bool, null)
      allow_privilege_escalation = optional(bool, null)
    }), null)
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Service Account
# ---------------------------------------------------------------------------

variable "service_account_name" {
  description = "Existing ServiceAccount name. Empty = use default."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Pod-level settings
# ---------------------------------------------------------------------------

variable "image_pull_secrets" {
  description = "List of image pull secret names."
  type        = list(string)
  default     = []
}

variable "node_selector" {
  description = "Node selector labels."
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Pod tolerations."
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Wait settings
# ---------------------------------------------------------------------------

variable "wait_for_rollout" {
  type        = bool
  description = "Whether to wait for the workload to be rolled out."
  default     = true
}

