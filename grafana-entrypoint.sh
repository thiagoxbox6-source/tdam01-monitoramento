#!/bin/bash
MODULE="/var/lib/grafana/plugins/alexanderzobnin-zabbix-app/datasource/module.js"
PATCH="/tmp/module_patched_v2.js"
MARKER="_iFiltered"

apply_patch() {
    if [ -f "$MODULE" ] && ! grep -q "$MARKER" "$MODULE" 2>/dev/null; then
        cp "$PATCH" "$MODULE"
        echo "[patch] null-guards aplicados em module.js"
    fi
}

/run.sh &
GRAFANA_PID=$!

echo "[patch] Monitor iniciado..."
for i in $(seq 1 24); do
    sleep 5
    apply_patch
done

wait $GRAFANA_PID
