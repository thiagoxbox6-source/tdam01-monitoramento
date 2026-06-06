# ============================================================
# TDAM01 — Melhorias no Zabbix
# - Corrige thresholds: Mem I/O e CPU no RT01-WAN
# - Adiciona itens: NAT translations, IP SLA RTT, erros de interface
# - Adiciona itens SW01-LAN: PoE, STP, Temperatura, Fan
# - Cria triggers para todos os novos itens
# ============================================================

param(
    [string]$ZabbixUrl = "http://localhost:8080",
    [string]$ZabbixUser = "Admin",
    [string]$ZabbixPass = ""
)

# Lê senha do .env se não foi passada
if (-not $ZabbixPass) {
    $envFile = Join-Path $PSScriptRoot ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match "^POSTGRES_PASSWORD=(.+)") { }  # ignored
        }
    }
    $ZabbixPass = Read-Host "Senha do Zabbix Admin (padrão: zabbix)"
    if (-not $ZabbixPass) { $ZabbixPass = "zabbix" }
}

$API = "$ZabbixUrl/api_jsonrpc.php"
$H   = @{ "Content-Type" = "application/json" }

function Zbx($method, $params, $auth = $null) {
    $body = @{ jsonrpc = "2.0"; method = $method; params = $params; id = 1 }
    if ($auth) { $body.auth = $auth }
    $r = Invoke-RestMethod -Uri $API -Method Post -Headers $H -Body ($body | ConvertTo-Json -Depth 20)
    if ($r.error) { throw "Zabbix API error [$method]: $($r.error.data)" }
    return $r.result
}

# ── Autenticar ────────────────────────────────────────────
Write-Host "`n[1/6] Autenticando no Zabbix..." -ForegroundColor Cyan
$TOKEN = Zbx "user.login" @{ username = $ZabbixUser; password = $ZabbixPass }
Write-Host "      Token obtido: $($TOKEN.Substring(0,8))..."

$RT01 = "10683"
$SW01 = "10684"

# ── Buscar interfaces SNMP dos hosts ─────────────────────
Write-Host "`n[2/6] Buscando interfaces SNMP..." -ForegroundColor Cyan
$ifRT01 = (Zbx "hostinterface.get" @{ hostids = @($RT01); output = @("interfaceid","type") } $TOKEN | Where-Object { $_.type -eq "2" })[0].interfaceid
$ifSW01 = (Zbx "hostinterface.get" @{ hostids = @($SW01); output = @("interfaceid","type") } $TOKEN | Where-Object { $_.type -eq "2" })[0].interfaceid
Write-Host "      RT01-WAN interfaceid: $ifRT01"
Write-Host "      SW01-LAN interfaceid: $ifSW01"

# ── PARTE 1: Corrigir thresholds existentes ──────────────
Write-Host "`n[3/6] Corrigindo thresholds de triggers..." -ForegroundColor Cyan

$triggers = Zbx "trigger.get" @{
    hostids = @($RT01)
    output  = @("triggerid","description","expression")
    expandExpression = $true
} $TOKEN

$updated = 0
foreach ($trig in $triggers) {
    $desc = $trig.description
    $expr = $trig.expression
    $newExpr = $null

    # CPU: Warning 80→70%, Critical 90→85%
    if ($desc -match "CPU.*high|High CPU" -and $expr -match ">(\s*)(80|90)") {
        if ($Matches[2] -eq "80") { $newExpr = $expr -replace ">(\s*)80", "> 70" }
        if ($Matches[2] -eq "90") { $newExpr = $expr -replace ">(\s*)90", "> 85" }
    }
    # Mem I/O: Warning 75→88%, Critical 90→95%
    if ($desc -match "I/O.*memory|memory.*I/O|Memory.*high" -and $expr -match "I.O") {
        if ($expr -match ">(\s*)75") { $newExpr = $expr -replace ">(\s*)75", "> 88" }
        if ($expr -match ">(\s*)90") { $newExpr = $expr -replace ">(\s*)90", "> 95" }
    }

    if ($newExpr -and $newExpr -ne $expr) {
        try {
            Zbx "trigger.update" @{ triggerid = $trig.triggerid; expression = $newExpr } $TOKEN | Out-Null
            Write-Host "      [OK] Trigger atualizado: $desc" -ForegroundColor Green
            $updated++
        } catch {
            Write-Host "      [WARN] $desc : $_" -ForegroundColor Yellow
        }
    }
}

if ($updated -eq 0) {
    Write-Host "      Nenhum threshold atualizado (triggers podem ter formato diferente — verifique manualmente)" -ForegroundColor Yellow
    Write-Host "      Listando triggers do RT01-WAN para referência:"
    $triggers | Where-Object { $_.description -match "CPU|Memory|mem" } | ForEach-Object {
        Write-Host "        ID=$($_.triggerid) | $($_.description)"
    }
}

# ── Helper: criar item se não existir ───────────────────
function New-ZbxItem($hostid, $ifid, $name, $key, $oid, $valueType, $delay = "60s", $units = "") {
    $existing = Zbx "item.get" @{ hostids = @($hostid); search = @{ key_ = $key }; output = @("itemid","name") } $TOKEN
    if ($existing.Count -gt 0) {
        Write-Host "      [SKIP] Já existe: $name (id=$($existing[0].itemid))" -ForegroundColor Gray
        return $existing[0].itemid
    }
    $params = @{
        hostid      = $hostid
        interfaceid = $ifid
        name        = $name
        key_        = $key
        type        = 20          # SNMP agent
        snmp_oid    = $oid
        value_type  = $valueType  # 0=float, 3=uint, 4=text
        delay       = $delay
        history     = "7d"
        trends      = "365d"
        status      = 0
    }
    if ($units) { $params.units = $units }
    $r = Zbx "item.create" $params $TOKEN
    Write-Host "      [OK] Item criado: $name (id=$($r.itemids[0]))" -ForegroundColor Green
    return $r.itemids[0]
}

# Helper: criar trigger se não existir
function New-ZbxTrigger($name, $expr, $severity, $recovery = "") {
    $existing = Zbx "trigger.get" @{ search = @{ description = $name }; output = @("triggerid") } $TOKEN
    if ($existing.Count -gt 0) {
        Write-Host "      [SKIP] Trigger já existe: $name" -ForegroundColor Gray
        return
    }
    $params = @{
        description = $name
        expression  = $expr
        priority    = $severity  # 0=not class, 1=info, 2=warn, 3=average, 4=high, 5=disaster
        status      = 0
    }
    if ($recovery) { $params.recovery_expression = $recovery; $params.recovery_mode = 1 }
    Zbx "trigger.create" $params $TOKEN | Out-Null
    Write-Host "      [OK] Trigger criado: $name" -ForegroundColor Green
}

# ── PARTE 2: Novos itens RT01-WAN ───────────────────────
Write-Host "`n[4/6] Criando itens para RT01-WAN..." -ForegroundColor Cyan

# NAT: total de traduções ativas (Cisco IP NAT MIB)
$natItemId = New-ZbxItem $RT01 $ifRT01 `
    "NAT: Active translations" `
    "nat.active.translations" `
    "1.3.6.1.4.1.9.9.291.1.3.1.1.0" `
    3 "60s" ""

# IP SLA RTT — instâncias 1 e 2 (WAN TIM e WAN VIVO)
# IMPORTANTE: confirme os índices com: snmpwalk -v2c -c <community> 192.168.100.1 1.3.6.1.4.1.9.9.42.1.2.1.1.2
$rttTIM  = New-ZbxItem $RT01 $ifRT01 `
    "IP SLA 1 (WAN TIM): RTT" `
    "ipsla.rtt[1]" `
    "1.3.6.1.4.1.9.9.42.1.2.10.1.1.1" `
    0 "60s" "ms"

$rttVIVO = New-ZbxItem $RT01 $ifRT01 `
    "IP SLA 2 (WAN VIVO): RTT" `
    "ipsla.rtt[2]" `
    "1.3.6.1.4.1.9.9.42.1.2.10.1.1.2" `
    0 "60s" "ms"

$rttSenseTIM  = New-ZbxItem $RT01 $ifRT01 `
    "IP SLA 1 (WAN TIM): Sense" `
    "ipsla.sense[1]" `
    "1.3.6.1.4.1.9.9.42.1.2.10.1.5.1" `
    3 "60s" ""

$rttSenseVIVO = New-ZbxItem $RT01 $ifRT01 `
    "IP SLA 2 (WAN VIVO): Sense" `
    "ipsla.sense[2]" `
    "1.3.6.1.4.1.9.9.42.1.2.10.1.5.2" `
    3 "60s" ""

# Interface errors Gi0/4 (WAN_VIVO) e Gi0/5 (WAN_TIM)
# ifIndex típico C841M: Gi0/4=5, Gi0/5=6 — CONFIRME com snmpwalk 1.3.6.1.2.1.2.2.1.2
Write-Host "      NOTA: ifIndex de Gi0/4 e Gi0/5 assumido como 5 e 6. Confirme com snmpwalk se não aparecer dado." -ForegroundColor Yellow

$errGi04In  = New-ZbxItem $RT01 $ifRT01 "Interface Gi0/4(WAN_VIVO): Input errors"   "if.in.errors[gi0/4]"   "1.3.6.1.2.1.2.2.1.14.5" 3 "120s" ""
$errGi04Out = New-ZbxItem $RT01 $ifRT01 "Interface Gi0/4(WAN_VIVO): Output discards" "if.out.discards[gi0/4]" "1.3.6.1.2.1.2.2.1.19.5" 3 "120s" ""
$errGi05In  = New-ZbxItem $RT01 $ifRT01 "Interface Gi0/5(WAN_TIM): Input errors"    "if.in.errors[gi0/5]"   "1.3.6.1.2.1.2.2.1.14.6" 3 "120s" ""
$errGi05Out = New-ZbxItem $RT01 $ifRT01 "Interface Gi0/5(WAN_TIM): Output discards"  "if.out.discards[gi0/5]" "1.3.6.1.2.1.2.2.1.19.6" 3 "120s" ""

# ── PARTE 3: Novos itens SW01-LAN ───────────────────────
Write-Host "`n[5/6] Criando itens para SW01-LAN..." -ForegroundColor Cyan

# PoE — watts consumidos totais (POWER-ETHERNET-MIB, módulo 1)
$poeUsed  = New-ZbxItem $SW01 $ifSW01 "PoE: Watts consumidos (módulo 1)"   "poe.consumption[1]"   "1.3.6.1.2.1.105.1.3.1.1.4.1" 0 "60s" "W"
$poeTotal = New-ZbxItem $SW01 $ifSW01 "PoE: Watts disponíveis (módulo 1)"  "poe.available[1]"     "1.3.6.1.2.1.105.1.3.1.1.2.1" 0 "300s" "W"

# STP Topology Changes (acumulado — usar change rate na trigger)
$stpChanges = New-ZbxItem $SW01 $ifSW01 "STP: Topology changes"  "stp.topchanges" "1.3.6.1.2.1.17.2.4.0" 3 "60s" ""

# Temperatura — ciscoEnvMonTemperatureTable index 1
$tempSW = New-ZbxItem $SW01 $ifSW01 "Temperature: CPU temperature value"  "envmon.temp[1]" "1.3.6.1.4.1.9.9.13.1.3.1.3.1" 0 "120s" "°C"

# Fan status — ciscoEnvMonFanTable index 1 (1=normal, 2=warning, 3=critical, 4=shutdown, 5=notPresent, 6=notFunctioning)
$fanStatus = New-ZbxItem $SW01 $ifSW01 "Fan: Status (módulo 1)"  "envmon.fan[1]" "1.3.6.1.4.1.9.9.13.1.4.1.3.1" 3 "120s" ""

# Uplink Gi1/0/49 errors
$errUpIn  = New-ZbxItem $SW01 $ifSW01 "Interface Gi1/0/49(UPLINK): Input errors"    "if.in.errors[gi1/0/49]"    "1.3.6.1.2.1.2.2.1.14.52" 3 "120s" ""
$errUpOut = New-ZbxItem $SW01 $ifSW01 "Interface Gi1/0/49(UPLINK): Output discards"  "if.out.discards[gi1/0/49]" "1.3.6.1.2.1.2.2.1.19.52" 3 "120s" ""

# ── PARTE 4: Triggers para novos itens ──────────────────
Write-Host "`n[6/6] Criando triggers para novos itens..." -ForegroundColor Cyan

# NAT translations
New-ZbxTrigger `
    "RT01-WAN: NAT translations acima de 12000 (limite: 15000)" `
    "last(/RT01-WAN/nat.active.translations)>12000" `
    3  # average

New-ZbxTrigger `
    "RT01-WAN: NAT translations crítico acima de 14000" `
    "last(/RT01-WAN/nat.active.translations)>14000" `
    4  # high

# IP SLA sense (1=ok, 2=disconnected, 3=dropped, 4=sequenceError, 5=verifyError, 6=timeout, ...)
New-ZbxTrigger `
    "RT01-WAN: WAN TIM - IP SLA fora do ar (sense != ok)" `
    "last(/RT01-WAN/ipsla.sense[1])<>1 and nodata(/RT01-WAN/ipsla.sense[1],120s)=0" `
    4  # high

New-ZbxTrigger `
    "RT01-WAN: WAN VIVO - IP SLA fora do ar (sense != ok)" `
    "last(/RT01-WAN/ipsla.sense[2])<>1 and nodata(/RT01-WAN/ipsla.sense[2],120s)=0" `
    4  # high

# RTT alto
New-ZbxTrigger `
    "RT01-WAN: WAN TIM - Latência alta (RTT > 100ms)" `
    "avg(/RT01-WAN/ipsla.rtt[1],5m)>100" `
    2  # warning

New-ZbxTrigger `
    "RT01-WAN: WAN VIVO - Latência alta (RTT > 100ms)" `
    "avg(/RT01-WAN/ipsla.rtt[2],5m)>100" `
    2  # warning

# Interface errors (delta em 5min > 0 indica erros ativos)
New-ZbxTrigger `
    "RT01-WAN: Erros em Gi0/4 (WAN_VIVO) detectados" `
    "change(/RT01-WAN/if.in.errors[gi0/4])>0 or change(/RT01-WAN/if.out.discards[gi0/4])>0" `
    2  # warning

New-ZbxTrigger `
    "RT01-WAN: Erros em Gi0/5 (WAN_TIM) detectados" `
    "change(/RT01-WAN/if.in.errors[gi0/5])>0 or change(/RT01-WAN/if.out.discards[gi0/5])>0" `
    2  # warning

# SW01 PoE
New-ZbxTrigger `
    "SW01-LAN: PoE consumo acima de 333W (90% de 370W)" `
    "last(/SW01-LAN/poe.consumption[1])>333" `
    3  # average

New-ZbxTrigger `
    "SW01-LAN: PoE consumo crítico acima de 352W (95% de 370W)" `
    "last(/SW01-LAN/poe.consumption[1])>352" `
    4  # high

# STP topology changes — delta > 3 em 5 min = instabilidade
New-ZbxTrigger `
    "SW01-LAN: Instabilidade STP - mudanças de topologia detectadas" `
    "change(/SW01-LAN/stp.topchanges)>3" `
    3  # average

# SW01 temperatura
New-ZbxTrigger `
    "SW01-LAN: Temperatura alta (> 60°C)" `
    "last(/SW01-LAN/envmon.temp[1])>60" `
    2  # warning

New-ZbxTrigger `
    "SW01-LAN: Temperatura crítica (> 70°C)" `
    "last(/SW01-LAN/envmon.temp[1])>70" `
    4  # high

# SW01 fan (qualquer valor != 1 = problema)
New-ZbxTrigger `
    "SW01-LAN: Fan com problema (status != normal)" `
    "last(/SW01-LAN/envmon.fan[1])<>1 and nodata(/SW01-LAN/envmon.fan[1],300s)=0" `
    3  # average

# Uplink errors
New-ZbxTrigger `
    "SW01-LAN: Erros no uplink Gi1/0/49 detectados" `
    "change(/SW01-LAN/if.in.errors[gi1/0/49])>0 or change(/SW01-LAN/if.out.discards[gi1/0/49])>0" `
    2  # warning

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  Melhorias aplicadas com sucesso!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "PRÓXIMOS PASSOS:" -ForegroundColor Yellow
Write-Host "  1. Confirme ifIndex das interfaces WAN:" -ForegroundColor White
Write-Host "     snmpwalk -v2c -c <community> 192.168.100.1 1.3.6.1.2.1.2.2.1.2"
Write-Host "     (Gi0/4 e Gi0/5 assumidos como index 5 e 6)"
Write-Host ""
Write-Host "  2. Confirme índices IP SLA configurados no roteador:" -ForegroundColor White
Write-Host "     snmpwalk -v2c -c <community> 192.168.100.1 1.3.6.1.4.1.9.9.42.1.2.1.1.2"
Write-Host "     (assumido SLA 1 = TIM, SLA 2 = VIVO)"
Write-Host ""
Write-Host "  3. Rode .\criar_dashboard_noc.ps1 para atualizar o dashboard Grafana" -ForegroundColor White
Write-Host ""
