resource "kubernetes_deployment_v1" "telemetrygen" {
  metadata {
    name      = "telemetrygen"
    namespace = "observability"
    labels    = { app = "telemetrygen" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "telemetrygen" }
    }

    template {
      metadata {
        labels = { app = "telemetrygen" }
      }

      spec {
        container {
          name              = "telemetrygen"
          image             = "ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen@sha256:ff5f0474cee382b12baa9af8d9133074e8d812ca99797c82266960787e7971c3"
          image_pull_policy = "IfNotPresent"
          args = [
            "traces",
            "--otlp-http",
            "--otlp-endpoint=otel-collector-opentelemetry-collector:4318", # <— kein http://
            "--otlp-insecure",                                             # http statt https erlauben
            "--otlp-http-url-path=/v1/traces",                             # sicherheitshalber explizit
            "--rate=5",
            "--workers=1",
            "--service=demo-telemetry",
            "--duration=1h"
          ]
          resources {
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }
}
