module "obs" {
  source               = "./modules/k8s-observability"
  cluster_name         = var.cluster_name
  enable_newrelic      = var.enable_newrelic
  newrelic_license_b64 = var.newrelic_license_b64
}
module "sonarqube" { source = "./modules/k8s-sonarqube" }
module "demo_telemetry" { source = "./modules/k8s-demo-telemetry" }
module "jaeger" { source = "./modules/k8s-jaeger" }
