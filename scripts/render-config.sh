#!/usr/bin/env bash
# Render environment-dependent monitoring config from .env.
#   - monitoring/targets/public.yml   (public uptime probe target)
#   - monitoring/alertmanager.yml     (Slack receiver only if SLACK_WEBHOOK_URL is set)
#   - monitoring/secrets/slack_webhook
set -euo pipefail
cd "$(dirname "$0")/.."

# Read only the keys we need. (Do not `source` .env: values may contain spaces.)
get() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' || true; }
PUBLIC_URL="$(get PUBLIC_URL)"
SLACK_WEBHOOK_URL="$(get SLACK_WEBHOOK_URL)"
: "${PUBLIC_URL:?PUBLIC_URL must be set in .env}"

mkdir -p monitoring/targets monitoring/secrets
cat > monitoring/targets/public.yml <<YAML
- targets: ["${PUBLIC_URL%/}/health"]
  labels: {probe: public}
YAML

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  printf '%s' "$SLACK_WEBHOOK_URL" > monitoring/secrets/slack_webhook
  chmod 644 monitoring/secrets/slack_webhook   # readable by the alertmanager container user
  RECEIVER=$(cat <<'YAML'
  - name: default
    slack_configs:
      - api_url_file: /etc/alertmanager/secrets/slack_webhook
        send_resolved: true
        title: '[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ "\n" }}{{ end }}'
YAML
)
else
  : > monitoring/secrets/slack_webhook
  RECEIVER="  - name: default   # no SLACK_WEBHOOK_URL set: alerts visible in Alertmanager UI only"
fi

cat > monitoring/alertmanager.yml <<YAML
global:
  resolve_timeout: 5m
route:
  receiver: default
  group_by: [alertname, instance]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
receivers:
${RECEIVER}
YAML
echo "Rendered monitoring config for ${PUBLIC_URL}"
