param()
$GRAFANA = "http://localhost:3000"
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:Graf@TDAM01!2025"))
$H = @{ Authorization = "Basic $b64"; "Content-Type" = "application/json" }

$DS_UID = (Invoke-RestMethod -Uri "$GRAFANA/api/datasources/name/Zabbix-TDAM01" -Headers $H).uid
Write-Host "Datasource UID: $DS_UID"

function T($hname, $iname, $ref = "A") {
    return @{
        refId          = $ref
        queryType      = "0"
        schema         = 12
        datasource     = @{ type = "alexanderzobnin-zabbix-datasource"; uid = $DS_UID }
        group          = @{ filter = "TDAM01" }
        host           = @{ filter = $hname }
        application    = @{ filter = "" }
        item           = @{ filter = $iname }
        itemTag        = @{ filter = "" }
        macro          = @{ filter = "" }
        trigger        = @{ filter = "" }
        tags           = @{ filter = "" }
        proxy          = @{ filter = "" }
        textFilter     = ""
        evaltype       = "0"
        countTriggers  = $false
        countTriggersBy = ""
        minSeverity    = 3
        mode           = 0
        resultFormat   = "time_series"
        functions      = @()
        options        = @{
            showDisabledItems      = $false
            skipEmptyValues        = $false
            useTrends              = "default"
            count                  = $false
            disableDataAlignment   = $false
            useZabbixValueMapping  = $false
        }
        table          = @{ skipEmptyValues = $false }
    }
}

function cpuThr   { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=70},@{color="red";value=85}) } }
function memThr   { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=75},@{color="red";value=90}) } }
function memIOThr { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=88},@{color="red";value=95}) } }
function tempThr  { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=60},@{color="red";value=75}) } }
function okThr    { @{ mode="absolute"; steps=@(@{color="green";value=$null}) } }
function natThr   { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=12000},@{color="red";value=14000}) } }
function rttThr   { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=60},@{color="red";value=150}) } }
function poeThr   { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=279},@{color="red";value=333}) } }

$ifMap = @{
    type = "value"
    options = @{
        "1" = @{ text="UP";   color="green"; index=0 }
        "2" = @{ text="DOWN"; color="red";   index=1 }
        "5" = @{ text="DORM"; color="blue";  index=2 }
        "6" = @{ text="N/P";  color="gray";  index=3 }
    }
}

function mkRow($id, $title, $y) {
    @{ id=$id; type="row"; title=$title; collapsed=$false; gridPos=@{x=0;y=$y;w=24;h=1}; panels=@() }
}

function mkStat($id, $title, $hname, $iname, $x, $y, $w, $h, $unit, $thr, $maps=@()) {
    @{
        id=$id; type="stat"; title=$title
        gridPos=@{x=$x;y=$y;w=$w;h=$h}
        datasource=@{type="alexanderzobnin-zabbix-datasource";uid=$DS_UID}
        targets=@(T $hname $iname)
        options=@{
            reduceOptions=@{calcs=@("lastNotNull");fields="";values=$false}
            colorMode="background"; graphMode="none"; textMode="value"; orientation="auto"
        }
        fieldConfig=@{
            defaults=@{unit=$unit;mappings=$maps;thresholds=$thr;color=@{mode="thresholds"};noValue="N/A"}
            overrides=@()
        }
        transformations=@()
    }
}

function mkTSSingle($id, $title, $hname, $iname, $x, $y, $w, $h, $unit = "short", $color = "blue") {
    @{
        id=$id; type="timeseries"; title=$title
        gridPos=@{x=$x;y=$y;w=$w;h=$h}
        datasource=@{type="alexanderzobnin-zabbix-datasource";uid=$DS_UID}
        targets=@(T $hname $iname)
        options=@{
            legend=@{displayMode="list";placement="bottom";showLegend=$true}
            tooltip=@{mode="single";sort="none"}
        }
        fieldConfig=@{
            defaults=@{
                unit=$unit; color=@{fixedColor=$color;mode="fixed"}
                custom=@{lineWidth=2;fillOpacity=12;gradientMode="opacity";showPoints="never"}
            }
            overrides=@()
        }
        transformations=@()
    }
}

function mkTSMulti($id, $title, $hname, $items, $x, $y, $w, $h, $unit = "ms") {
    # $items = array of @{label; iname; color}
    $targets = @()
    $overrides = @()
    $ref = 65  # ASCII 'A'
    foreach ($it in $items) {
        $targets += T $hname $it.iname ([char]$ref).ToString()
        $overrides += @{
            matcher    = @{ id="byName"; options=([char]$ref).ToString() }
            properties = @(@{ id="displayName"; value=$it.label },@{ id="color"; value=@{fixedColor=$it.color;mode="fixed"} })
        }
        $ref++
    }
    @{
        id=$id; type="timeseries"; title=$title
        gridPos=@{x=$x;y=$y;w=$w;h=$h}
        datasource=@{type="alexanderzobnin-zabbix-datasource";uid=$DS_UID}
        targets=$targets
        options=@{ legend=@{displayMode="list";placement="bottom";showLegend=$true}; tooltip=@{mode="multi";sort="none"} }
        fieldConfig=@{
            defaults=@{ unit=$unit; color=@{mode="palette-classic"}; custom=@{lineWidth=2;fillOpacity=10;gradientMode="opacity";showPoints="never"} }
            overrides=$overrides
        }
        transformations=@()
    }
}

function mkGauge($id, $title, $hname, $iname, $x, $y, $w, $h, $unit, $thr, $min=0, $max=100) {
    @{
        id=$id; type="gauge"; title=$title
        gridPos=@{x=$x;y=$y;w=$w;h=$h}
        datasource=@{type="alexanderzobnin-zabbix-datasource";uid=$DS_UID}
        targets=@(T $hname $iname)
        options=@{
            reduceOptions=@{calcs=@("lastNotNull");fields="";values=$false}
            orientation="auto"; showThresholdLabels=$false; showThresholdMarkers=$true
        }
        fieldConfig=@{
            defaults=@{unit=$unit;min=$min;max=$max;thresholds=$thr;color=@{mode="thresholds"};noValue="N/A"}
            overrides=@()
        }
        transformations=@()
    }
}

function mkTS($id, $title, $hname, $iIn, $iOut, $x, $y, $w, $h) {
    @{
        id=$id; type="timeseries"; title=$title
        gridPos=@{x=$x;y=$y;w=$w;h=$h}
        datasource=@{type="alexanderzobnin-zabbix-datasource";uid=$DS_UID}
        targets=@((T $hname $iIn "IN"), (T $hname $iOut "OUT"))
        options=@{
            legend=@{displayMode="list";placement="bottom";showLegend=$true}
            tooltip=@{mode="multi";sort="none"}
        }
        fieldConfig=@{
            defaults=@{
                unit="bps"; color=@{mode="palette-classic"}
                custom=@{lineWidth=2;fillOpacity=15;gradientMode="opacity";showPoints="never"}
            }
            overrides=@(
                @{matcher=@{id="byName";options="IN"};  properties=@(@{id="color";value=@{fixedColor="green"; mode="fixed"}})}
                @{matcher=@{id="byName";options="OUT"}; properties=@(@{id="color";value=@{fixedColor="orange";mode="fixed"}})}
            )
        }
        transformations=@()
    }
}

$panels = [System.Collections.ArrayList]::new()
$i = 1

# RT01-WAN
$null = $panels.Add((mkRow $i++ "RT01-WAN - Firewall Cisco C841M - 192.168.100.1" 0))

$null = $panels.Add((mkStat $i++ "Uptime"          "RT01-WAN" "Uptime (network)"                                    0  1 4 4 "dtdhms"  (okThr)))
$null = $panels.Add((mkStat $i++ "CPU %"           "RT01-WAN" "#1: CPU utilization"                                 4  1 4 4 "percent" (cpuThr)))
$null = $panels.Add((mkStat $i++ "Mem Processor %" "RT01-WAN" "Processor: Memory utilization"                       8  1 4 4 "percent" (memThr)))
$null = $panels.Add((mkStat $i++ "Mem I/O %"       "RT01-WAN" "I/O: Memory utilization"                           12  1 4 4 "percent" (memIOThr)))
$null = $panels.Add((mkStat $i++ "Temp CPU"        "RT01-WAN" "CPU temperature: Temperature"                       16  1 4 4 "celsius" (tempThr)))
$null = $panels.Add((mkStat $i++ "WAN TIM"         "RT01-WAN" "Interface Gi0/5(WAN_TIM): Operational status"       20  1 2 4 "none"    (okThr) @($ifMap)))
$null = $panels.Add((mkStat $i++ "WAN VIVO"        "RT01-WAN" "Interface Gi0/4(WAN_VIVO): Operational status"      22  1 2 4 "none"    (okThr) @($ifMap)))

$vlans = @(
    @{n="Vl1 MGMT";   it="Interface Vl1(MGMT_VLAN_GERENCIAMENTO): Operational status"; x=0}
    @{n="Vl5 PROD";   it="Interface Vl5(REDE_PRODUCAO_ISOLADA): Operational status";   x=4}
    @{n="Vl10 WiFi";  it="Interface Vl10(WIFI_GERAL): Operational status";             x=8}
    @{n="Vl20 GW";    it="Interface Vl20(GATEWAY_WIFI): Operational status";           x=12}
    @{n="Vl30 TV";    it="Interface Vl30(VLAN_STREAMING_TV): Operational status";      x=16}
)
foreach ($v in $vlans) {
    $null = $panels.Add((mkStat $i++ $v.n "RT01-WAN" $v.it $v.x 5 4 3 "none" (okThr) @($ifMap)))
}

$null = $panels.Add((mkTS $i++ "Trafego WAN TIM (Gi0/5)"  "RT01-WAN" "Interface Gi0/5(WAN_TIM): Bits received"  "Interface Gi0/5(WAN_TIM): Bits sent"  0  8 12 8))
$null = $panels.Add((mkTS $i++ "Trafego WAN VIVO (Gi0/4)" "RT01-WAN" "Interface Gi0/4(WAN_VIVO): Bits received" "Interface Gi0/4(WAN_VIVO): Bits sent" 12 8 12 8))

# Latência WAN (IP SLA RTT)
$null = $panels.Add((mkTSMulti $i++ "Latencia WAN - RTT (IP SLA)" "RT01-WAN" @(
    @{ label="TIM RTT";  iname="IP SLA 1 (WAN TIM): RTT";  color="green"  }
    @{ label="VIVO RTT"; iname="IP SLA 2 (WAN VIVO): RTT"; color="orange" }
) 0 16 12 6 "ms"))

# NAT Translations ativas
$null = $panels.Add((mkTSSingle $i++ "NAT: Traducoes ativas" "RT01-WAN" "NAT: Active translations" 12 16 6 6 "short" "purple"))

# NAT Gauge (limite 15k)
$null = $panels.Add((mkGauge $i++ "NAT: Uso atual" "RT01-WAN" "NAT: Active translations" 18 16 6 6 "short" (natThr) 0 15000))

# SW01-LAN
$swY = 22  # y base da seção SW01 (após novos painéis RT01)
$null = $panels.Add((mkRow $i++ "SW01-LAN - Cisco Catalyst 2960X - 192.168.100.2" $swY))

$null = $panels.Add((mkStat  $i++ "Uptime"   "SW01-LAN" "Uptime (network)"            0  ($swY+1) 4 3 "dtdhms"  (okThr)))
$null = $panels.Add((mkStat  $i++ "CPU %"    "SW01-LAN" "#1: CPU utilization"         4  ($swY+1) 4 3 "percent" (cpuThr)))
$null = $panels.Add((mkStat  $i++ "Mem %"    "SW01-LAN" "I/O: Memory utilization"     8  ($swY+1) 4 3 "percent" (memThr)))
$null = $panels.Add((mkStat  $i++ "Temp CPU" "SW01-LAN" "Temperature: CPU temperature value" 12 ($swY+1) 3 3 "celsius" (tempThr)))
$null = $panels.Add((mkStat  $i++ "Fan"      "SW01-LAN" "Fan: Status (módulo 1)"      15 ($swY+1) 3 3 "short"   (okThr)))
$null = $panels.Add((mkStat  $i++ "STP Changes" "SW01-LAN" "STP: Topology changes"   18 ($swY+1) 3 3 "short"   @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=1},@{color="red";value=10}) }))

# PoE gauge (budget: 370W)
$null = $panels.Add((mkGauge $i++ "PoE: Consumo (budget 370W)" "SW01-LAN" "PoE: Watts consumidos (módulo 1)" 21 ($swY+1) 3 3 "watt" (poeThr) 0 370))

# Uplink + STP timeline
$null = $panels.Add((mkTS    $i++ "Uplink SW01 -> RT01-WAN" "SW01-LAN" "Interface Gi1/0/49(UPLINK_TO_RT01_WAN): Bits received" "Interface Gi1/0/49(UPLINK_TO_RT01_WAN): Bits sent" 0 ($swY+4) 16 6))
$null = $panels.Add((mkTSSingle $i++ "PoE: Consumo ao longo do tempo" "SW01-LAN" "PoE: Watts consumidos (módulo 1)" 16 ($swY+4) 8 6 "watt" "orange"))

$dash = @{
    dashboard = @{
        id = $null; uid = "tdam01-noc-v1"
        title = "TDAM01 - NOC Dashboard"
        tags = @("TDAM01","NOC")
        timezone = "America/Sao_Paulo"
        refresh = "30s"; schemaVersion = 39; version = 1
        time = @{ from = "now-3h"; to = "now" }
        graphTooltip = 1; editable = $true
        panels = $panels.ToArray()
        templating = @{ list = @() }
        annotations = @{ list = @() }
        links = @()
    }
    folderId = 0; overwrite = $true; message = "NOC v3 - itens reais do Zabbix"
}

$body   = $dash | ConvertTo-Json -Depth 20 -Compress
$result = Invoke-RestMethod -Uri "$GRAFANA/api/dashboards/db" -Method Post -Headers $H -Body $body
Write-Host "[OK] $GRAFANA$($result.url)"
