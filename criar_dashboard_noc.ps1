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

function cpuThr  { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=60},@{color="red";value=85}) } }
function memThr  { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=75},@{color="red";value=90}) } }
function tempThr { @{ mode="absolute"; steps=@(@{color="green";value=$null},@{color="yellow";value=60},@{color="red";value=75}) } }
function okThr   { @{ mode="absolute"; steps=@(@{color="green";value=$null}) } }

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
$null = $panels.Add((mkStat $i++ "Mem I/O %"       "RT01-WAN" "I/O: Memory utilization"                           12  1 4 4 "percent" (memThr)))
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

# SW01-LAN
$null = $panels.Add((mkRow $i++ "SW01-LAN - Cisco Catalyst 2960X - 192.168.100.2" 16))

$null = $panels.Add((mkStat $i++ "Uptime" "SW01-LAN" "Uptime (network)"              0  17 4 4 "dtdhms"  (okThr)))
$null = $panels.Add((mkStat $i++ "CPU %"  "SW01-LAN" "#1: CPU utilization"           4  17 4 4 "percent" (cpuThr)))
$null = $panels.Add((mkStat $i++ "Mem %"  "SW01-LAN" "I/O: Memory utilization"       8  17 4 4 "percent" (memThr)))
$null = $panels.Add((mkTS   $i++ "Uplink SW01 -> RT01-WAN" "SW01-LAN" "Interface Gi1/0/49(UPLINK_TO_RT01_WAN): Bits received" "Interface Gi1/0/49(UPLINK_TO_RT01_WAN): Bits sent" 12 17 12 4))

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
