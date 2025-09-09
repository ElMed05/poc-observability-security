# Titel

**DevSecOps & Observability PoC**
Minikube · OpenTofu/Terraform · SonarQube · Wiz · Checkov/Conftest · OpenTelemetry · Jaeger

*Ziel:* Wie dieser PoC Architektur, Security & Compliance messbar verbessert – und wie ich ihn in CV & Interview verkaufe.

---

# Agenda

1. Ausgangslage & Ziele
2. Architekturüberblick
3. Pipeline & Prüfungen (IaC + Code)
4. Observability-Flow (Traces)
5. Automatisierung & Reproduzierbarkeit
6. Business Value
7. Erweiterungen (Azure, New Relic, Nexus)
8. Demo-Plan & Learnings
9. Q\&A

*Notes:* Gesamt-Story in 8–12 Minuten; optional Live-Demo (2–3 Min.).

---

# Ausgangslage & Ziele

**Ausgangslage**

* Heterogene Tool-Landschaft, Sicherheitsanforderungen steigen.
* IaC wächst – Qualität/Compliance müssen automatisiert werden.

**Ziele des PoC**

* *Shift-left Security:* IaC- und Code-Qualität bereits im PR prüfen.
* *Observability by default:* Traces sichtbar machen, Feedback-Loops verkürzen.
* *Infra-as-Code:* Wiederholbare, auditierbare Deployments.

*Notes:* Fokus auf messbare Effekte: weniger Fehl-Deployments, schnellere Fehleranalyse.

---

# Architekturüberblick (High-Level)

```
Dev → GitHub (PR) ──► GitHub Actions
  ├─ Checkov/Conftest/Wiz (IaC-Policy & Security)
  ├─ SonarQube (Codequalität)
  └─ (optional) Gated Apply → Minikube

Minikube Cluster
  ├─ telemetrygen (synthetic load)
  ├─ OpenTelemetry Collector
  │     ├─ debug exporter (stdout)
  │     └─ OTLP → Jaeger
  └─ Jaeger (UI) – Trace-Analyse
```

*Notes:* Zeigt Trennung von CI-Validierung und Runtime-Observability.

---

# Stack: Komponenten

* **OpenTofu/Terraform**: IaC für Namespaces, Helm-Releases, Deployments.
* **Checkov + Conftest (OPA)**: Policy-as-Code für Terraform & K8s.
* **Wiz** (optional im CI): tiefergehende IaC-Bewertung, Kurzreport & Fail-on-High.
* **SonarQube**: Codequalität, Quality Gate „New Code“.
* **OTel Collector + telemetrygen**: Traces generieren & einsammeln.
* **Jaeger**: UI für Traces (Search/Latency/Causes).
* **Makefile**: Developer UX, Ein-Befehl-Workflows (up, apply, sonar-open, jaeger-open …).

*Notes:* Betonung: Standardtools, vendor-neutral, lokal reproduzierbar.

---

# CI-Pipeline (IaC & Code)

**Schritte**

1. `tofu plan` → `plan.json`
2. **Checkov** Scan (Terraform+K8s) + Job-Summary
3. **Conftest/OPA** auf `plan.json` (Regeln z. B. no public svc, Ressourcengrenzen, Labels)
4. **Wiz** (optional) – Top-3-Findings + Fail-on-High/Critical
5. **SonarQube** Scan + Quality Gate

**Gate**

* Build schlägt fehl bei HIGH/CRITICAL (Checkov/Wiz) oder Quality Gate „Failed“.

*Notes:* „Sicherheit als Eintrittskarte in den Deploy-Schritt“.

---

# Observability-Flow (Traces)

**Datenfluss**

* `telemetrygen` → OTLP gRPC → **OTel Collector** → **Jaeger (OTLP)**
* Collector-eigene Metriken: :8889 (Health/Errors sichtbar)

**Nutzen**

* Zeit bis zur Ursachenfindung sinkt (Trace-Timeline, Spans, Fehler-Tags).
* Synthetic load beweist den End-to-End-Weg schon vor App-Integration.

*Notes:* In der Demo „demo-telemetry“ als Service in Jaeger suchen.

---

# Automatisierung & Reproduzierbarkeit

* **Makefile**: `up`, `apply`, `scan-all`, `sonar-open`, `jaeger-open`, `sonar-health`.
* **Port-Forward-Handling** robust (tmux/ensure-pf), Friendly URLs.
* **Idempotente IaC**: klarer Desired State, `destroy`-Cleanup.
* **Lockfile** für Provider-Versionen (deterministisches Build).

*Notes:* Für Reviewer: minimale Einarbeitung, schnelle Reproduzierbarkeit.

---

# Business Value (für Fachbereich)

* **Schnellerer Feedback-Loop**: Qualität & Security in Minuten statt Tagen.
* **Geringeres Risiko**: Policies stoppen unsichere Konfigurationen früh.
* **Transparenz**: Traces visualisieren Latenzen & Fehlerpfade.
* **Compliance**: Nachvollziehbarkeit via IaC, nachvollziehbare Prüfberichte (Artefakte im CI).

*Notes:* Zahlenbeispiele anbieten (z. B. 30–50 % schnellere Störungsanalyse in PoC).

---

# Erweiterungen (Roadmap)

**Azure-Fokus**

* `azurerm`-Module (RG, KV, Log Analytics; optional AKS).
* Azure Policy/Initiatives als Code; Entra-ID SP für RBAC.

**APM/Monitoring**

* **New Relic** via OTLP/HTTP Exporter (api-key Header, EU Endpoint).
* **Prometheus + Grafana** für Metriken.

**Supply Chain**

* **Nexus** als Artefakt-Proxy/Registry (Docker/Helm/Maven);
  SBOM (syft), Signaturen (cosign), Policies (Kyverno/Gatekeeper).

**GitOps**

* Argo CD/Flux für kontinuierliche Auslieferung.

*Notes:* Roadmap zeigt Reifegrad & Anschlussfähigkeit.

---

# Demo-Plan (2–3 Minuten)

1. **CI-Summary**: Zeige Checkov/Wiz/Sonar-Ergebnis im letzten Run.
2. **Jaeger UI**: `demo-telemetry` → Traces anzeigen; kurze Analyse.
3. **Policy in Action**: kleine unsichere Änderung lokal, `scan-all` → Fail zeigen.

*Notes:* Immer mit „Warum wichtig fürs Business“ verknüpfen.

---

# Lessons Learned

* **Kleine Schritte, harte Gates** schlagen „Big Bang“-Deploys.
* **Defaults killen Risiken**: Policies, Ressourcen-Limits, No-Public-Services als Standard.
* **DX zählt**: Makefile & klare Readme senken Onboarding-Zeit.

*Notes:* Reife Organisationspraxis betonen (standards, templates, automation-first).

---

# Elevator Pitch (60 Sekunden)

„Ich habe einen **End-to-End DevSecOps PoC** gebaut: IaC mit OpenTofu, **automatische Security- und Compliance-Prüfungen** (Checkov, OPA, Wiz) schon im PR und **Observability out of the box** mit OpenTelemetry+Jaeger. Das Ganze läuft **reproduzierbar auf Minikube**, gesteuert über ein **Makefile**. Ergebnis: **Fehlerhafte Deployments werden früh gestoppt**, Codequalität ist messbar (SonarQube), und **Traces verkürzen die Fehlersuche**. Erweiterbar Richtung **Azure & New Relic**. Das ist die Basis, um **schneller, sicherer und auditierbar** in die Cloud zu liefern.“

---

# Interview-Highlights (zum Einbauen in CV/Antworten)

* **„Shift-left Security umgesetzt“**: IaC-Policies + Quality Gates stoppen Risiken vor Deploy.
* **„Observability integriert“**: Traces via OTel/Jaeger, schnellere RCA.
* **„Reproduzierbare Plattform“**: Minikube + OpenTofu + Helm, Makefile-Automation.
* **„Compliance & Nachvollziehbarkeit“**: Artefakte (plan.json, Checkov/Wiz Reports, Sonar) im CI.
* **„Cloud-ready“**: optionaler Azure-Connector, OTLP zu New Relic, GitOps-Perspektive.

*Notes:* Diese Bullet-Points direkt im CV unter „Relevante Projekte“ platzieren.

---

# Q\&A – typische Rückfragen & Kurzantworten

**Q:** Warum OpenTofu statt Terraform?
**A:** Funktionsgleich im PoC; Open-Source-Governance; Lockfile für reproduzierbare Provider.

**Q:** Wie skaliert das?
**A:** Module/Policies sind wiederverwendbar; GitHub Environments & GitOps für Staging/Prod.

**Q:** Wie passt New Relic rein?
**A:** OTel Collector OTLP/HTTP Exporter (api-key Header), parallel zu Jaeger.

**Q:** Was ist der erste Schritt in Azure?
**A:** RG+KV+LogAnalytics als IaC, Service Principal, dann AKS oder Landing Zone.

---

# Backup: Kurz-Variante (5 Folien)

1. Problem & Ziel
2. Architektur & Pipeline auf 1 Slide
3. Security Gates (Checkov/OPA/Wiz) + Sonar
4. Observability (OTel → Jaeger)
5. Business Value & Next Steps (Azure, New Relic, Nexus)

*Notes:* Für knappe Slots, 3–5 Minuten.\*
