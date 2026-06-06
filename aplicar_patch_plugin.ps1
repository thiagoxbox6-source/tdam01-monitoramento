#!/usr/bin/env pwsh
# aplicar_patch_plugin.ps1 — Aplica patches de null-guard no plugin Zabbix do Grafana
# Execute DEPOIS de iniciar a stack: docker compose up -d
# Os patches sobrevivem enquanto o container nao for recriado.
# Ao recriar (docker compose up -d), execute este script novamente.

param(
    [string]$Container = "tdam01-grafana",
    [int]$WaitSeconds = 15
)

Write-Host "Aguardando Grafana inicializar e instalar o plugin ($WaitSeconds s)..." -ForegroundColor Cyan
Start-Sleep -Seconds $WaitSeconds

$MODULE = "/var/lib/grafana/plugins/alexanderzobnin-zabbix-app/datasource/module.js"
$PATCH  = "C:\monitoramento\module_patched_v2.js"

# Verifica se o arquivo existe no container
$check = docker exec $Container sh -c "test -f $MODULE && echo OK || echo MISS"
if ($check -ne "OK") {
    Write-Host "[ERRO] Plugin nao encontrado em $MODULE" -ForegroundColor Red
    Write-Host "Verifique se o Grafana terminou de instalar o plugin." -ForegroundColor Yellow
    exit 1
}

# Verifica se ja esta patcheado
$alreadyPatched = docker exec $Container sh -c "grep -c '_iFiltered' $MODULE 2>/dev/null || echo 0"
if ([int]$alreadyPatched -gt 0) {
    Write-Host "[OK] Patch ja aplicado (_iFiltered encontrado). Nada a fazer." -ForegroundColor Green
    exit 0
}

# Aplica o patch
Write-Host "Aplicando patch no module.js..." -ForegroundColor Yellow
docker cp $PATCH "${Container}:${MODULE}"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERRO] Falha ao copiar arquivo para o container" -ForegroundColor Red
    exit 1
}

# Verifica
$patches = docker exec $Container sh -c "grep -o '_iFiltered\|__fe\|if(!r)return!1;for\|if(!t)return 0' $MODULE | wc -l"
Write-Host "[OK] Patches aplicados: $patches ocorrencias encontradas" -ForegroundColor Green
Write-Host ""
Write-Host "Dashboard NOC disponivel em: http://localhost:3000/d/tdam01-noc-v1/" -ForegroundColor Cyan
