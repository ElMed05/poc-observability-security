# poc-observability-security
Minikube + OpenTofu + Helm
- Observability: OTel Collector (optional New Relic)
- Codequalität: SonarQube (Helm)
- Guardrails: Checkov + OPA/Conftest
# Poc workflow
telemetrygen  ──OTLP gRPC──▶  OpenTelemetry Collector  ──debug──▶  (stdout der Collector-Logs)
                                     ▲
                                     └── eigene Metrics auf :8888/:8889
