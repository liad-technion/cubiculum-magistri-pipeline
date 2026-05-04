#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?VERSION must be set}"

for _ in $(seq 1 30); do
    if curl -sf http://localhost:8000/ >/dev/null; then
        break
    fi
    sleep 1
done

PAYLOAD=$(curl -s http://localhost:8000/)
echo "Service responded: ${PAYLOAD}"

ACTUAL=$(echo "${PAYLOAD}" | jq -r .version)
if [ "${ACTUAL}" != "${VERSION}" ]; then
    echo "Version mismatch: expected ${VERSION}, got ${ACTUAL}" >&2
    exit 1
fi

echo "Smoke test passed: version=${ACTUAL}"