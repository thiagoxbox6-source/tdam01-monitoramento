# ============================================================
# TDAM01 — Adicionar Oxidized à stack de monitoramento
# ============================================================

$ErrorActionPreference = "Stop"
$stackDir = "C:\monitoramento"
$oxidizedDir = "$stackDir\oxidized"

Write-Host "`n[1/5] Criando diretorios necessarios..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "$oxidizedDir\crashes" | Out-Null
New-Item -ItemType Directory -Force -Path "$oxidizedDir\oxidized.git" | Out-Null
Write-Host "      OK: $oxidizedDir" -ForegroundColor Green

Write-Host "`n[2/5] Baixando imagem do Oxidized..." -ForegroundColor Cyan
Set-Location $stackDir
docker compose pull oxidized
if (-not $?) { Write-Host "ERRO: Falha ao baixar imagem." -ForegroundColor Red; exit 1 }

Write-Host "`n[3/5] Subindo container oxidized..." -ForegroundColor Cyan
docker compose up -d oxidized
if (-not $?) { Write-Host "ERRO: Falha ao iniciar container." -ForegroundColor Red; exit 1 }

Write-Host "`n[4/5] Aguardando Oxidized inicializar (30s)..." -ForegroundColor Cyan
$timeout = 60
$elapsed = 0
$ready = $false
while ($elapsed -lt $timeout) {
    Start-Sleep -Seconds 5
    $elapsed += 5
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:8888/nodes" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
    Write-Host "      Aguardando... ($elapsed/$timeout s)" -ForegroundColor Yellow
}

if ($ready) {
    Write-Host "      Oxidized respondendo na porta 8888!" -ForegroundColor Green
} else {
    Write-Host "      AVISO: Oxidized ainda nao respondeu. Verifique com: docker logs tdam01-oxidized" -ForegroundColor Yellow
}

Write-Host "`n[5/5] Abrindo interface web..." -ForegroundColor Cyan
Start-Process "http://localhost:8888"

Write-Host "`n=== Oxidized adicionado com sucesso! ===" -ForegroundColor Green
Write-Host "  Web UI:       http://192.168.0.100:8888"
Write-Host "  RT01-WAN:     http://192.168.0.100:8888/node/show/RT01-WAN"
Write-Host "  SW01-LAN:     http://192.168.0.100:8888/node/show/SW01-LAN"
Write-Host "  Logs:         docker logs -f tdam01-oxidized"
Write-Host "  Status nodes: docker exec tdam01-oxidized oxidized-reload"
Write-Host ""
