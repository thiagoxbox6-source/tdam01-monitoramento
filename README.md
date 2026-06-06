# TDAM01 — Stack de Monitoramento de Rede

Stack completa de monitoramento para redes com equipamentos Cisco, usando **Zabbix 7** + **Grafana** rodando em Docker no Windows 11 Pro (WSL2/Docker Desktop).

![Grafana](https://img.shields.io/badge/Grafana-10.4.3-orange) ![Zabbix](https://img.shields.io/badge/Zabbix-7.0.27-red) ![Docker](https://img.shields.io/badge/Docker-Compose-blue) ![SNMP](https://img.shields.io/badge/SNMP-v2c-green) ![Oxidized](https://img.shields.io/badge/Oxidized-0.37-purple)

## 📊 Dashboard NOC

Dados reais coletados via SNMP v2c de equipamentos Cisco:

| Dispositivo | Métricas monitoradas |
|-------------|---------------------|
| **RT01-WAN** Cisco C841M | Uptime, CPU %, Memória (Processor + I/O), Temperatura CPU, Status WANs (TIM/VIVO), Status VLANs (5x), Tráfego por interface |
| **SW01-LAN** Cisco Catalyst 2960X | Uptime, CPU %, Memória, Tráfego uplink |

## 🏗️ Arquitetura

```
Docker Compose
├── PostgreSQL 15          — banco do Zabbix
├── Zabbix Server 7.0.27   — coleta SNMP v2c
├── Zabbix Web (nginx)     — interface web :8080
├── Zabbix Agent2          — monitora o host
├── Grafana 10.4.3         — dashboards :3000
│   └── Plugin: alexanderzobnin-zabbix-app v6.3.2
├── Grafana Image Renderer — exportação de imagens :8081
└── Oxidized 0.37          — backup de configs via SSH+Git :8888
```

## 🚀 Como usar

### Pré-requisitos

- Docker Desktop com WSL2 (Windows 11)
- PowerShell 7+

### 1. Clone e configure

```powershell
git clone https://github.com/SEU_USUARIO/tdam01-monitoramento.git
cd tdam01-monitoramento

# Copie e edite as credenciais
cp .env.example .env
notepad .env
```

### 2. Suba a stack

```powershell
docker compose up -d
```

Aguarde ~30 segundos para todos os serviços iniciarem.

### 3. Aplique o patch do plugin Grafana

> **Necessário após cada `docker compose up -d`** — o Grafana re-baixa o plugin e sobrescreve o patch.

```powershell
.\aplicar_patch_plugin.ps1
```

O script aguarda 15s e aplica automaticamente os null-guards no plugin.

### 4. Configure o Zabbix

Acesse http://localhost:8080 (Admin / zabbix) e adicione os hosts com interface SNMP v2c.  
Ou use o script automático:

```powershell
python adicionar_hosts_zabbix.py
```

### 5. Configure a datasource no Grafana

Acesse http://localhost:3000, vá em **Plugins → Zabbix → Enable**, depois:
- **Configuration → Data Sources → Add → Zabbix**
- URL: `http://zabbix-web:8080/api_jsonrpc.php`
- Username: `Admin` / Password: `zabbix`

### 6. Gere o dashboard NOC

```powershell
.\criar_dashboard_noc.ps1
```

Dashboard em: **http://localhost:3000/d/tdam01-noc-v1/**  
Modo kiosk: adicione `?kiosk` na URL

## 📁 Estrutura de arquivos

```
.
├── docker-compose.yml          # Stack completa (incluindo Oxidized)
├── .env.example                # Template de variáveis (copiar para .env)
├── instalar.ps1                # Setup inicial da stack
├── adicionar_hosts_zabbix.py   # Adiciona hosts no Zabbix via API
├── adicionar_oxidized.ps1      # Deploy do Oxidized na stack
├── criar_dashboard_noc.ps1     # Gera o dashboard NOC no Grafana
├── aplicar_patch_plugin.ps1    # Aplica null-guards no plugin após docker compose up
├── module_patched_v2.js        # Plugin JS com patches de null-guard
├── oxidized/
│   ├── config                  # Configuração do Oxidized (SSH→Git, porta 8888)
│   └── router.db               # Lista de devices (RT01-WAN, SW01-LAN)
└── zabbix/
    └── grafana/provisioning/   # Provisioning do Grafana
```

## 🔧 Fix do bug no plugin Zabbix para Grafana

O plugin `alexanderzobnin-zabbix-app v6.3.2` tem um bug: quando o backend retorna DataFrames com valores `null` (Zabbix retorna null para itens sem coleta recente), a função `seriesToDataFrame` crasha com:

```
TypeError: Cannot read properties of null (reading '1')
```

**6 patches aplicados em `module_patched_v2.js`:**
- `seriesToDataFrame` — filtra datapoints nulos antes de mapear
- `applyFrontendFunctions` — null-guard em `Fe()` 
- `isConvertibleToWide` — null-guard em `r.values.get()`
- `timeShift` e `ge()` — null-guard em resultado de `regex.exec()`
- `sortTimeseries` — filtra nulls antes do sort

O script `aplicar_patch_plugin.ps1` substitui o `module.js` automaticamente após o Grafana instalar o plugin.

## ⚙️ Thresholds

| Métrica | Aviso | Crítico |
|---------|-------|---------|
| CPU | 60% | 85% |
| Memória | 75% | 90% |
| Temperatura | 60°C | 75°C |

## 💾 Oxidized — Backup de Configurações

O Oxidized conecta via SSH nos devices Cisco e salva o `running-config` automaticamente com histórico de versões via Git.

| Campo | Valor |
|-------|-------|
| Devices | RT01-WAN (192.168.100.1), SW01-LAN (192.168.100.2) |
| Protocolo | SSH — modelo `ios` |
| Intervalo | 3600 segundos (1 hora) |
| Storage | Git bare repo em `oxidized/oxidized.git/` |
| Interface web | http://SERVER_IP:8888 |
| IP Docker | 172.20.0.16 |

### Adicionar o Oxidized à stack

```powershell
.\adicionar_oxidized.ps1
```

### URLs de acesso

```
http://192.168.0.100:8888                        # Lista de todos os nodes
http://192.168.0.100:8888/node/show/RT01-WAN     # Config atual do roteador
http://192.168.0.100:8888/node/show/SW01-LAN     # Config atual do switch
```

### Logs e troubleshooting

```powershell
docker logs -f tdam01-oxidized          # Acompanhar coletas em tempo real
docker exec tdam01-oxidized cat /home/oxidized/.config/oxidized/crash  # Ver crash
```

## 📝 Licença

MIT
