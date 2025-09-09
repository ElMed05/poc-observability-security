variable "cluster_name" { type = string }
variable "enable_newrelic" { type = bool }
variable "newrelic_license_b64" { type = string }

resource "kubernetes_namespace" "obs" {
  metadata {
    name = "observability"
  }
}

resource "kubernetes_secret" "newrelic" {
  count = var.enable_newrelic ? 1 : 0

  metadata {
    name      = "newrelic-license"
    namespace = kubernetes_namespace.obs.metadata[0].name
  }

  data = {
    license = var.newrelic_license_b64 # bereits Base64
  }
  type = "Opaque"
}

resource "helm_release" "newrelic_bundle" {
  count      = var.enable_newrelic ? 1 : 0
  name       = "newrelic-bundle"
  repository = "https://helm-charts.newrelic.com"
  chart      = "nri-bundle"
  namespace  = kubernetes_namespace.obs.metadata[0].name

  values = [
    yamlencode({
      global = {
        cluster          = var.cluster_name
        licenseKeySecret = { name = "newrelic-license", key = "license" }
      }
      newrelic-infrastructure = { enabled = true }
      kube-state-metrics      = { enabled = true }
      prometheus              = { enabled = true }
      otel                    = { enabled = true }
    })
  ]
}

# Fallback ohne New Relic: OTel Collector, exportiert ins Log
resource "helm_release" "otel_collector" {
  count      = var.enable_newrelic ? 0 : 1
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace.obs.metadata[0].name

  timeout         = 600
  atomic          = false
  force_update    = true
  cleanup_on_fail = true

  values = [
  yamlencode({
    image = {
      repository = "otel/opentelemetry-collector-k8s"
      tag        = "0.104.0"
    }
    mode = "deployment"

    config = {
      receivers  = { otlp = { protocols = { http = {}, grpc = {} } } }
      processors = { batch = {} }
      exporters  = {
        # → schickt Traces an Jaeger-OTLP Service (gRPC)
        otlp  = {
          endpoint = "jaeger-otlp.observability.svc.cluster.local:4317"
          tls = { insecure = true }
        }
        debug = { verbosity = "detailed" }
      }
      service = {
        telemetry = { metrics = { address = "0.0.0.0:8889" } }
        pipelines = {
          traces  = { receivers = ["otlp"], processors = ["batch"], exporters = ["otlp","debug"] }
          metrics = { receivers = ["otlp"], processors = ["batch"], exporters = ["debug"] }
          logs    = { receivers = ["otlp"], processors = ["batch"], exporters = ["debug"] }
        }
      }
    }
  })
]

}
