#!/bin/sh
# OpenClaw container entrypoint
# POSIX-compatible script for config generation and gateway startup

set -e

CONFIG_DIR="/config"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
TEMPLATE_FILE="/etc/openclaw/config-template.json"

# Allowlisted environment variables (security: only substitute known vars)
ALLOWLIST="OPENCLAW_MATRIX_TOKEN ELEVENLABS_API_KEY MOONSHOT_API_KEY OPENROUTER_API_KEY WHATSAPP_NUMBER WHATSAPP_BOT_NUMBER"

mkdir -p "${CONFIG_DIR}"

if [ ! -f "${TEMPLATE_FILE}" ]; then
    echo "ERROR: Config template not found at ${TEMPLATE_FILE}" >&2
    exit 1
fi

cp "${TEMPLATE_FILE}" "${CONFIG_FILE}"

# Substitute allowlisted environment variables
for var_name in ${ALLOWLIST}; do
    var_value=$(eval printf '%s' "\$$var_name")
    if [ -n "${var_value}" ]; then
        escaped_value=$(printf '%s' "${var_value}" | sed 's/[\\/&]/\\&/g')
        escaped_value=$(printf '%s' "${escaped_value}" | sed ':a;N;$!ba;s/\n/\\n/g')
        sed -i "s|\\\${${var_name}}|${escaped_value}|g" "${CONFIG_FILE}"
        echo "Substituted: ${var_name}"
    fi
done

echo "Config generated at: ${CONFIG_FILE}"
exec openclaw gateway --port 18789 "$@"
