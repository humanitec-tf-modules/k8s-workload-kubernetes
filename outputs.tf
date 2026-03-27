output "humanitec_metadata" {
  description = "Metadata for Humanitec."
  value = merge(
    {
      "Kubernetes-Namespace" = var.namespace
    },
    local.has_service ? { "Kubernetes-Service" = kubernetes_service_v1.this[0].metadata[0].name } : {},
    local.is_deployment ? { "Kubernetes-Deployment" = kubernetes_deployment_v1.this[0].metadata[0].name } : {},
    local.is_statefulset ? { "Kubernetes-StatefulSet" = kubernetes_stateful_set_v1.this[0].metadata[0].name } : {},
    local.is_cronjob ? { "Kubernetes-CronJob" = kubernetes_cron_job_v1.this[0].metadata[0].name } : {}
  )
}

output "endpoint" {
  description = "An optional Kubernetes service DNS hostname that the workload's service ports will be exposed on if any are defined"
  value       = local.has_service ? "${var.name}.${var.namespace}.svc.cluster.local" : null
}

output "service_name" {
  description = "Kubernetes service name"
  value       = local.has_service ? kubernetes_service_v1.this[0].metadata[0].name : null
}

