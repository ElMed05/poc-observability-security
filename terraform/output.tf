output "sonarqube_monitoring_passcode" {
  value     = module.sonarqube.monitoring_passcode
  sensitive = true
}
