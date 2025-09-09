# Namespace "observability" existiert bereits bei dir

# --- Deployment ---
resource "kubernetes_deployment_v1" "jaeger" {
  metadata {
    name      = "jaeger"
    namespace = "observability"
    labels    = { app = "jaeger" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "jaeger" } }
    template {
      metadata { labels = { app = "jaeger" } }
      spec {
        container {
          name  = "jaeger"
          image = "jaegertracing/all-in-one:1.72.0" # gut für PoC, in-memory

          # OTLP aktivieren (Collector nimmt dann :4317/:4318 an)
          env {
            name  = "COLLECTOR_OTLP_ENABLED"
            value = "true"
          }

          # >>> ACHTUNG: Blockname 'port' (singular)
          port {
            name           = "query"
            container_port = 16686
          }
          port {
            name           = "otlp-grpc"
            container_port = 4317
          }
          port {
            name           = "otlp-http"
            container_port = 4318
          }

          resources {
            limits   = { cpu = "500m", memory = "512Mi" }
            requests = { cpu = "100m", memory = "256Mi" }
          }
        }
      }
    }
  }
}

# --- Service fürs UI (NodePort) ---
resource "kubernetes_service_v1" "jaeger_query" {
  metadata {
    name      = "jaeger-query"
    namespace = "observability"
    labels    = { app = "jaeger" }
  }
  spec {
    selector = { app = "jaeger" }
    type     = "NodePort"

    port {
      name        = "http-query"
      port        = 16686
      target_port = "query"
      node_port   = 31686 # optional fest; sonst Zeile löschen
    }
  }
}

# --- Service für OTLP (ClusterIP) ---
resource "kubernetes_service_v1" "jaeger_otlp" {
  metadata {
    name      = "jaeger-otlp"
    namespace = "observability"
    labels    = { app = "jaeger" }
  }
  spec {
    selector = { app = "jaeger" }
    type     = "ClusterIP"

    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = "otlp-grpc"
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = "otlp-http"
    }
  }
}
