# =========[ Settings ]=========
SHELL := /bin/bash
.ONESHELL:
.SILENT: sonar-health # Damit die Shell-Befehle nicht mitgedruckt werden
TF_DIR        ?= terraform
TF_VARS       ?= $(TF_DIR)/envs/local.tfvars
KUBECONFIG    ?= $(HOME)/.kube/config

SONAR_NS      ?= sonarqube
OBS_NS        ?= observability

OTEL_DEPLOY        ?= otel-collector-opentelemetry-collector
TELEMETRY_DEPLOY   ?= telemetrygen

# Wiz CLI ( Eher optional)
WIZCLI       ?= ./wizcli
WIZ_ID       ?=
WIZ_SECRET   ?=

# Sonar local URL (bei Port-Forward)
SONAR_URL    ?= http://localhost:9000

# =========[ Help ]=========
.PHONY: help
help: ## Liste aller Targets
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?##' $(MAKEFILE_LIST) | sed 's/:.*##/: /' | sort

# =========[ Local env ]=========
.PHONY: env-check
env-check: ## Prüft grundlegende Tools (kubectl/helm/tofu)
	@which kubectl >/dev/null || (echo "kubectl fehlt" && exit 1)
	@which helm >/dev/null    || (echo "helm fehlt" && exit 1)
	@which tofu >/dev/null    || (echo "tofu fehlt" && exit 1)
	@echo "✅ Tools ok"

.PHONY: minikube-start
minikube-start: ## Startet Minikube (Docker-Driver)
	minikube start --driver=docker

.PHONY: kube-ctx
kube-ctx: ## Zeigt aktuellen kube-context
	kubectl config current-context

# =========[ OpenTofu/Terraform ]=========
.PHONY: fmt
fmt: ## Format Terraform/OpenTofu Code
	tofu fmt -recursive

.PHONY: validate
validate: ## tofu validate
	cd $(TF_DIR) && tofu validate

.PHONY: plan
plan: ## tofu plan + plan.json erzeugen
	cd $(TF_DIR) && tofu init
	cd $(TF_DIR) && tofu validate
	cd $(TF_DIR) && tofu plan -out=tfplan -var-file=$(TF_VARS)
	cd $(TF_DIR) && tofu show -json tfplan > ../plan.json
	@echo "📄 plan.json erzeugt"

.PHONY: apply
apply: ## tofu apply (nutzt $(TF_VARS))
	cd $(TF_DIR) && tofu apply -auto-approve -var-file=$(TF_VARS)

.PHONY: destroy
destroy: ## tofu destroy (löscht alles aus diesem Stack)
	cd $(TF_DIR) && tofu destroy -auto-approve -var-file=$(TF_VARS)

# =========[ Policy & Scans ]=========
.PHONY: opa
opa: plan ## Conftest/OPA gegen plan.json
	conftest test plan.json -p policy

.PHONY: checkov
checkov: ## Checkov Scan (Terraform+K8s) → checkov.json + Kurz-Summary
	checkov -d terraform --framework terraform,kubernetes -o json > checkov.json
	@echo "## 🔍 Checkov – Kurzfassung"
	@jq -r '(.results.failed_checks // []) | group_by(.severity) | map({sev:(.[0].severity),count:length}) | (["Severity","Count"], (.[]|[.sev,(.count|tostring)])) | @tsv' checkov.json | column -t

.PHONY: wiz-install
wiz-install: ## Lädt Wiz CLI lokal
	curl -fsSL -o $(WIZCLI) https://downloads.wiz.io/wizcli/latest/wizcli-linux-amd64
	chmod +x $(WIZCLI)
	$(WIZCLI) --version

.PHONY: wiz-login
wiz-login: ## Wiz Login (env WIZ_ID/WIZ_SECRET erforderlich)
	@[ -n "$(WIZ_ID)" ] && [ -n "$(WIZ_SECRET)" ] || (echo "Bitte WIZ_ID und WIZ_SECRET exportieren"; exit 1)
	$(WIZCLI) auth --id "$(WIZ_ID)" --secret "$(WIZ_SECRET)"

.PHONY: wiz-scan
wiz-scan: plan ## Wiz IaC Scan (terraform/ + plan.json) → Reports
	@[ -x "$(WIZCLI)" ] || $(MAKE) wiz-install
	$(MAKE) wiz-login
	$(WIZCLI) iac scan --path ./terraform -o wiz-iac.json,json
	$(WIZCLI) iac scan --path ./plan.json  -o wiz-plan.json,json
	@echo "## 🛡️ Wiz – Kurzfassung"
	@jq -s 'def C:{CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4}; [inputs | ..|objects|select(has("severity"))]|group_by(.severity)|map({sev:(.[0].severity),count:length})|sort_by(.sev|C[.])' wiz-iac.json wiz-plan.json

# =========[ Kubernetes Handy-Targets ]=========
.PHONY: pods
pods: ## Pods in beiden Namespaces
	kubectl get pods -n $(SONAR_NS)
	kubectl get pods -n $(OBS_NS)

.PHONY: pods-watch
pods-watch: ## Live-Pod-Status (watch) in beiden Namespaces
	@echo "=== $(SONAR_NS) ==="; kubectl get pods -n $(SONAR_NS) -w & \
	 echo "=== $(OBS_NS) ==="; kubectl get pods -n $(OBS_NS) -w

.PHONY: logs-otel
logs-otel: ## Tail Logs vom OTel-Collector
	kubectl -n $(OBS_NS) logs deploy/$(OTEL_DEPLOY) --tail=100 -f

.PHONY: logs-telemetry
logs-telemetry: ## Tail Logs vom telemetrygen
	kubectl -n $(OBS_NS) logs deploy/$(TELEMETRY_DEPLOY) --tail=100 -f

.PHONY: restart-telemetry
restart-telemetry: ## Rollout-Restart telemetrygen
	kubectl -n $(OBS_NS) rollout restart deploy/$(TELEMETRY_DEPLOY)

.PHONY: helm-status-otel
helm-status-otel: ## Helm-Status des Collector-Releases
	helm -n $(OBS_NS) status otel-collector || true

.PHONY: helm-uninstall-otel
helm-uninstall-otel: ## Collector-Release deinstallieren + Reste löschen
	-helm -n $(OBS_NS) uninstall otel-collector
	-kubectl -n $(OBS_NS) delete secret -l "owner=helm,name=otel-collector"
	-kubectl -n $(OBS_NS) delete configmap -l "owner=helm,name=otel-collector"

# =========[ Services & URLs ]=========
.PHONY: services
services: ## Minikube Service-Übersicht
	minikube service list

.PHONY: svc-list
svc-list: ## K8s Services in allen Namespaces
	kubectl get svc -A

.PHONY: nodeports
nodeports: ## NodePorts aller Services
	kubectl get svc -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,PORTS:.spec.ports[*].nodePort' | column -t

.PHONY: svc-url
svc-url: ## URL eines Services: make svc-url NS=<namespace> SVC=<service-name>
	@[ -n "$(NS)" ] || (echo "❌ Bitte NS=<namespace> setzen"; exit 1)
	@[ -n "$(SVC)" ] || (echo "❌ Bitte SVC=<service-name> setzen"; exit 1)
	@TYPE=$$(kubectl -n $(NS) get svc $(SVC) -o jsonpath='{.spec.type}'); \
	if [ "$$TYPE" = "NodePort" ]; then \
	  PORT=$$(kubectl -n $(NS) get svc $(SVC) -o jsonpath='{.spec.ports[0].nodePort}'); \
	  HOST=$$(minikube ip); \
	  URL="http://$$HOST:$$PORT"; \
	else \
	  URL=$$(minikube service -n $(NS) $(SVC) --url | head -n1); \
	fi; \
	echo $$URL

.PHONY: svc-open
svc-open: ## Service im Browser öffnen: make svc-open NS=<namespace> SVC=<service-name>
	@[ -n "$(NS)" ] || (echo "❌ Bitte NS=<namespace> setzen"; exit 1)
	@[ -n "$(SVC)" ] || (echo "❌ Bitte SVC=<service-name> setzen"; exit 1)
	@TYPE=$$(kubectl -n $(NS) get svc $(SVC) -o jsonpath='{.spec.type}'); \
	if [ "$$TYPE" = "NodePort" ]; then \
	  PORT=$$(kubectl -n $(NS) get svc $(SVC) -o jsonpath='{.spec.ports[0].nodePort}'); \
	  HOST=$$(minikube ip); \
	  URL="http://$$HOST:$$PORT"; \
	else \
	  URL=$$(minikube service -n $(NS) $(SVC) --url | head -n1); \
	fi; \
	echo "🌐 $$URL"; \
	if command -v wslview >/dev/null 2>&1; then wslview "$$URL"; \
	elif uname -r | grep -qi microsoft; then cmd.exe /c start "$$URL"; \
	elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$$URL"; \
	elif command -v open >/dev/null 2>&1; then open "$$URL"; \
	else echo "Bitte Browser manuell öffnen: $$URL"; fi

# SonarQube Convenience
.PHONY: sonar-url
sonar-url: ## Zeigt Sonar-URL (NodePort oder Port-Forward)
	@$(MAKE) --no-print-directory svc-url NS=$(SONAR_NS) SVC=sonarqube-sonarqube


# =========[ Port-Forward SonarQube – stabil via tmux ]=========
.PHONY: pf-start
pf-start: ## Startet Port-Forward in tmux-Sitzung 'sonar-pf' (Fallback: Vordergrund)
	@if command -v tmux >/dev/null 2>&1; then \
	  if tmux has-session -t sonar-pf 2>/dev/null; then \
	    echo "↪️  tmux-Session 'sonar-pf' läuft bereits"; \
	  else \
	    echo "🔌 starte Port-Forward in tmux-Session 'sonar-pf' ..."; \
	    tmux new-session -d -s sonar-pf "kubectl -n $(SONAR_NS) port-forward svc/sonarqube-sonarqube 9000:9000"; \
	  fi; \
	else \
	  echo "⚠️  tmux nicht installiert – starte Port-Forward im Vordergrund (Strg+C beendet)"; \
	  kubectl -n $(SONAR_NS) port-forward svc/sonarqube-sonarqube 9000:9000; \
	fi

.PHONY: ensure-pf
ensure-pf: ## Startet PF falls nötig und wartet kurz, bis Sonar antwortet
	@if ! curl -sf $(SONAR_URL)/api/system/status >/dev/null 2>&1; then \
	  $(MAKE) --no-print-directory pf-start >/dev/null; \
	  for i in {1..20}; do \
	    curl -sf $(SONAR_URL)/api/system/status >/dev/null 2>&1 && break; \
	    sleep 0.5; \
	  done; \
	fi

.PHONY: sonar-open
sonar-open: ## Öffnet SonarQube im Browser (startet PF falls nötig)
	@$(MAKE) --no-print-directory ensure-pf
	@echo "🌐 $(SONAR_URL)"
	@if command -v wslview >/dev/null 2>&1; then wslview $(SONAR_URL); \
	elif uname -r | grep -qi microsoft; then cmd.exe /c start $(SONAR_URL); \
	elif command -v xdg-open >/dev/null 2>&1; then xdg-open $(SONAR_URL); \
	elif command -v open >/dev/null 2>&1; then open $(SONAR_URL); \
	else echo "Bitte manuell öffnen: $(SONAR_URL)"; fi

.PHONY: pf-stop
pf-stop: ## Stoppt Port-Forward (tmux-Session + als Fallback pkill)
	@bash -lc '\
echo "🧹 stoppe Port-Forward ..."; \
if command -v tmux >/dev/null 2>&1 && tmux has-session -t sonar-pf 2>/dev/null; then \
  tmux send-keys -t sonar-pf C-c; sleep 1; tmux kill-session -t sonar-pf >/dev/null 2>&1 || true; \
fi; \
pkill -f "kubectl.*port-forward.*sonarqube.*9000:9000" >/dev/null 2>&1 || true; \
echo "🛑 Port-Forward beendet"'



.PHONY: pf-status
pf-status: ## Zeigt laufende Port-Forwards / tmux-Session
	@if command -v tmux >/dev/null 2>&1 && tmux has-session -t sonar-pf 2>/dev/null; then \
	  echo "tmux: Session 'sonar-pf' aktiv"; \
	else \
	  ps aux | grep -E "kubectl.*port-forward.*(sonarqube).*9000:9000" | grep -v grep || echo "keine Port-Forwards aktiv"; \
	fi

.PHONY: sonar-health
sonar-health: ## Healthcheck: erst public /api/system/status, optional Health/Metrics mit Token/Passcode
	URL="$(SONAR_URL)"
# 1) Public status (kein Login nötig)
	if ! curl -sf "$$URL/api/system/status" >/dev/null 2>&1; then
	  $(MAKE) --no-print-directory ensure-pf >/dev/null
	fi
	echo "status:"
	curl -s "$$URL/api/system/status"; echo
# 2) Optional: Health (braucht Token) oder Monitoring-Metrics (Passcode)
	if [ -n "$$SONAR_TOKEN" ]; then
	  echo "health:"
	  curl -s -u "$$SONAR_TOKEN:" "$$URL/api/system/health"; echo
	else
	  PASS=$$(cd $(TF_DIR) && tofu output -raw sonarqube_monitoring_passcode 2>/dev/null || true)
	  if [ -n "$$PASS" ]; then
	    echo "metrics (first 10 lines):"
	    curl -s -H "X-Sonar-Passcode: $$PASS" "$$URL/api/monitoring/metrics" | head -n 10
	  fi
	fi




# =========[ Convenience Kombis ]=========
.PHONY: scan-all
scan-all: fmt plan checkov opa ## fmt → plan → Checkov → OPA

.PHONY: up
up: env-check minikube-start apply pods ## Alles hochfahren & Status zeigen

.PHONY: down
down: destroy ## Alles löschen
