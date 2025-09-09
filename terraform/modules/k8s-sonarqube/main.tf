resource "kubernetes_namespace" "sq" {
  metadata {
    name = "sonarqube"
  }
}
resource "random_password" "monitoring_passcode" {
  length  = 24
  special = false
}


resource "helm_release" "sonarqube" {
  name       = "sonarqube"
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  namespace  = kubernetes_namespace.sq.metadata[0].name

  values = [
    yamlencode({
      community          = { enabled = true }
      monitoringPasscode = random_password.monitoring_passcode.result

      # -> gültiges Bitnami-Image erzwingen (kein 'bitnamilegacy')
      postgresql = {
        enabled = true
        image = {
          registry   = "docker.io"
          repository = "bitnami/postgresql"
          tag        = "16.4.0-debian-12-r0" # fester, existierender Tag
          pullPolicy = "IfNotPresent"
        }
      }

      service     = { type = "NodePort" }
      persistence = { enabled = true, size = "8Gi" }
      resources   = { requests = { cpu = "500m", memory = "1Gi" } }
    })
  ]


}

output "monitoring_passcode" {
  value     = random_password.monitoring_passcode.result
  sensitive = true
}

