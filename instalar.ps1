# ============================================================
# TDAM01 — Instalador do Stack de Monitoramento
# Zabbix 7.0 + Grafana via Docker Desktop no Windows 11
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$MonitoringDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Write-Step { param($msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "    [X]  $msg" -ForegroundColor Red; exit 1 }

# ── 1. Verifica / instala Docker Desktop ─────────────────────
Write-Step "Verificando Docker Desktop"

$dockerPath = (Get-Command docker -ErrorAction SilentlyContinue)?.Source
if ($dockerPath) {
    $v = docker version --format "{{.Server.Version}}" 2>$null
    Write-OK "Docker já instalado — Engine $v"
} else {
    Write-Warn "Docker Desktop não encontrado. Instalando via winget..."
    winget install --id Docker.DockerDesktop --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao instalar Docker Desktop via winget." }

    Write-Warn "Docker Desktop instalado. Aguardando inicialização (60s)..."
    Start-Sleep -Seconds 60

    $env:PATH += ";C:\Program Files\Docker\Docker\resources\bin"
    $dockerPath = (Get-Command docker -ErrorAction SilentlyContinue)?.Source
    if (-not $dockerPath) { Write-Fail "Docker não encontrado no PATH após instalação. Reinicie e rode novamente." }
    Write-OK "Docker Desktop instalado com sucesso."
}

# ── 2. Garante que o daemon está rodando ──────────────────────
Write-Step "Verificando se o daemon Docker está ativo"
$retries = 0
while ($retries -lt 10) {
    $info = docker info 2>$null
    if ($LASTEXITCODE -eq 0) { Write-OK "Daemon ativo."; break }
    $retries++
    Write-Warn "Aguardando daemon... ($retries/10)"
    Start-Sleep -Seconds 6
}
if ($retries -eq 10) { Write-Fail "Docker daemon não respondeu após 60s. Verifique o Docker Desktop." }

# ── 3. Verifica docker compose ───────────────────────────────
Write-Step "Verificando docker compose"
docker compose version 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "docker compose plugin não encontrado. Atualize o Docker Desktop." }
Write-OK "docker compose disponível."

# ── 4. Navega para o diretório do projeto ────────────────────
Set-Location $MonitoringDir

# ── 5. Verifica arquivos obrigatórios ────────────────────────
Write-Step "Verificando arquivos da stack"
@("docker-compose.yml", ".env") | ForEach-Object {
    if (-not (Test-Path $_)) { Write-Fail "Arquivo obrigatório não encontrado: $_" }
    Write-OK "$_"
}

# ── 6. Pull das imagens ──────────────────────────────────────
Write-Step "Baixando imagens Docker (pode demorar na primeira vez)"
docker compose pull
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao baixar imagens." }
Write-OK "Imagens baixadas."

# ── 7. Sobe os containers ────────────────────────────────────
Write-Step "Subindo containers"
docker compose up -d --remove-orphans
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao subir containers." }
Write-OK "Containers iniciados."

# ── 8. Aguarda Zabbix Web ficar pronto ───────────────────────
Write-Step "Aguardando Zabbix Web ficar pronto"
$retries = 0
while ($retries -lt 20) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:8080/" -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) { Write-OK "Zabbix Web respondendo."; break }
    } catch {}
    $retries++
    Write-Warn "Aguardando Zabbix Web... ($retries/20)"
    Start-Sleep -Seconds 10
}
if ($retries -eq 20) { Write-Warn "Zabbix Web ainda não respondeu — verifique 'docker compose logs zabbix-web'." }

# ── 9. Aguarda Grafana ───────────────────────────────────────
Write-Step "Aguardando Grafana ficar pronto"
$retries = 0
while ($retries -lt 15) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) { Write-OK "Grafana respondendo."; break }
    } catch {}
    $retries++
    Write-Warn "Aguardando Grafana... ($retries/15)"
    Start-Sleep -Seconds 10
}

# ── 10. Ativa plugin Zabbix no Grafana via API ───────────────
Write-Step "Ativando plugin alexanderzobnin-zabbix-app no Grafana"
$grafanaBase = "http://localhost:3000"
$grafanaCred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:Graf@TDAM01!2025"))
$headers = @{ Authorization = "Basic $grafanaCred"; "Content-Type" = "application/json" }

try {
    $body = '{"enabled": true}'
    $r = Invoke-RestMethod -Uri "$grafanaBase/api/plugins/alexanderzobnin-zabbix-app/settings" `
        -Method Post -Headers $headers -Body $body -ErrorAction Stop
    Write-OK "Plugin Zabbix ativado no Grafana."
} catch {
    Write-Warn "Não foi possível ativar o plugin via API agora — ative manualmente em: Grafana > Plugins > Zabbix"
}

# ── 11. Resumo final ─────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  TDAM01 — Stack de Monitoramento iniciado com sucesso!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Zabbix Web  : http://192.168.0.100:8080  (Admin / zabbix)" -ForegroundColor White
Write-Host "  Grafana     : http://192.168.0.100:3000  (admin / Graf@TDAM01!2025)" -ForegroundColor White
Write-Host ""
Write-Host "  Próximo passo: execute adicionar_hosts_zabbix.py" -ForegroundColor Yellow
Write-Host "    python adicionar_hosts_zabbix.py" -ForegroundColor Yellow
Write-Host ""

docker compose ps
