#!/usr/bin/env bash
set -euo pipefail

SONAR_URL="${SONAR_URL:-http://localhost:9000}"
SONAR_USER="${SONAR_USER:-admin}"
SONAR_PASS="${SONAR_PASS:-admin}"

PROJECT_KEY="${PROJECT_KEY:-poc-observability-security}"
PROJECT_NAME="${PROJECT_NAME:-POC Observability + Security}"
QG_NAME="${QG_NAME:-Strict on New Code}"

auth() {
  # Basic-Auth Header erzeugen
  printf "%s" "$1:$2" | base64
}

HEADER_AUTH="Authorization: Basic $(auth "$SONAR_USER" "$SONAR_PASS")"

echo "→ SonarQube @ $SONAR_URL erreichbar?"
curl -sf "$SONAR_URL/api/system/status" >/dev/null || { echo "Sonar nicht erreichbar (Port-Forward?)"; exit 1; }

# 1) Projekt anlegen (idempotent)
echo "→ Projekt anlegen (falls nicht vorhanden): $PROJECT_KEY"
if ! curl -sf -H "$HEADER_AUTH" "$SONAR_URL/api/projects/search?projects=$PROJECT_KEY" | jq -e '.components|length>0' >/dev/null; then
  curl -sf -H "$HEADER_AUTH" -X POST \
    "$SONAR_URL/api/projects/create?project=$PROJECT_KEY&name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PROJECT_NAME'))")" >/dev/null
  echo "  ✔ erstellt"
else
  echo "  ✔ existiert bereits"
fi

# 2) Quality Gate anlegen (idempotent)
echo "→ Quality Gate: $QG_NAME"
QG_ID=$(curl -sf -H "$HEADER_AUTH" "$SONAR_URL/api/qualitygates/list" | jq -r --arg n "$QG_NAME" '.qualitygates[]|select(.name==$n)|.id' || true)
if [ -z "${QG_ID:-}" ] || [ "$QG_ID" = "null" ]; then
  curl -sf -H "$HEADER_AUTH" -X POST "$SONAR_URL/api/qualitygates/create?name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$QG_NAME'))")" >/dev/null
  QG_ID=$(curl -sf -H "$HEADER_AUTH" "$SONAR_URL/api/qualitygates/list" | jq -r --arg n "$QG_NAME" '.qualitygates[]|select(.name==$n)|.id')
  echo "  ✔ erstellt (ID=$QG_ID)"
else
  echo "  ✔ existiert (ID=$QG_ID)"
fi

# Helper: Condition anlegen (wenn nicht vorhanden)
add_cond () {
  local metric="$1" op="$2" error="$3"
  # prüfen ob Bedingung schon existiert
  if ! curl -sf -H "$HEADER_AUTH" "$SONAR_URL/api/qualitygates/show?id=$QG_ID" \
      | jq -e --arg m "$metric" '.conditions[]?|select(.metric==$m)' >/dev/null; then
    curl -sf -H "$HEADER_AUTH" -X POST \
      "$SONAR_URL/api/qualitygates/create_condition?gateId=$QG_ID&metric=$metric&op=$op&error=$error" >/dev/null
    echo "  + condition: $metric $op $error"
  else
    echo "  = condition vorhanden: $metric"
  fi
}

echo "→ Bedingungen (New Code) hinzufügen"
# Ratings: 1 = A, 2 = B, ...
add_cond new_reliability_rating        GT 1     # muss A sein
add_cond new_security_rating           GT 1
add_cond new_maintainability_rating    GT 1
add_cond new_coverage                  LT 80    # mindestens 80%
add_cond new_duplicated_lines_density  GT 3     # max 3%
# Optional (wenn Hotspots genutzt werden):
# add_cond new_security_hotspots_reviewed LT 100

# 3) Gate dem Projekt zuweisen
echo "→ Gate dem Projekt zuweisen"
curl -sf -H "$HEADER_AUTH" -X POST "$SONAR_URL/api/qualitygates/select?gateName=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$QG_NAME'))")&projectKey=$PROJECT_KEY" >/dev/null
echo "  ✔ zugewiesen"

# 4) New Code Period setzen (seit vorheriger Version)
echo "→ New Code Period = PREVIOUS_VERSION"
curl -sf -H "$HEADER_AUTH" -X POST "$SONAR_URL/api/new_code_periods/set?project=$PROJECT_KEY&type=PREVIOUS_VERSION" >/dev/null \
  || curl -sf -H "$HEADER_AUTH" -X POST "$SONAR_URL/api/new_code_periods/set?project=$PROJECT_KEY&type=NUMBER_OF_DAYS&value=30" >/dev/null
echo "  ✔ gesetzt"

echo "→ Fertig."
