#!/usr/bin/env python3
"""
TDAM01 — Cadastro automático de hosts no Zabbix via API
Equipamentos: RT01-WAN (Cisco C841M)
SNMP v2c | Zabbix 7.0
"""

import json
import sys
import time
import urllib.request
import urllib.error
from typing import Any

# ── Configurações ─────────────────────────────────────────────
ZABBIX_URL    = "http://localhost:8080/api_jsonrpc.php"
ZABBIX_USER   = "Admin"
ZABBIX_PASS   = "zabbix"
SNMP_COMMUNITY = "NOC@7klcuzEu6G3d!2025"

HOSTS = {
    "RT01-WAN": {
        "ip": "192.168.100.1",
        "description": "Firewall Cisco C841M-4X/K9 | IOS 15.9(3)M8 | Dual WAN TIM/VIVO",
        "templates": [
            "Cisco IOS SNMP",
            "Cisco IOS by SNMP",
        ],
        "groups": ["Network devices", "Firewalls", "TDAM01"],
        "tags": [
            {"tag": "site",    "value": "TDAM01"},
            {"tag": "role",    "value": "firewall"},
            {"tag": "vendor",  "value": "Cisco"},
            {"tag": "model",   "value": "C841M-4X"},
            {"tag": "wan1",    "value": "TIM-Gi0/5"},
            {"tag": "wan2",    "value": "VIVO-Gi0/4"},
        ],
    },
    "SW01-LAN": {
        "ip": "192.168.100.2",
        "description": "Switch Cisco Catalyst 2960X-48LPS-L | 48x GE PoE + 4x SFP uplink",
        "templates": [
            "Cisco IOS by SNMP",
        ],
        "groups": ["Network devices", "Switches", "TDAM01"],
        "tags": [
            {"tag": "site",    "value": "TDAM01"},
            {"tag": "role",    "value": "switch"},
            {"tag": "vendor",  "value": "Cisco"},
            {"tag": "model",   "value": "2960X-48LPS-L"},
            {"tag": "uplink",  "value": "RT01-WAN"},
        ],
    },
}


def zabbix_call(session_id: str | None, method: str, params: dict) -> Any:
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1,
    }
    if session_id:
        payload["auth"] = session_id

    data = json.dumps(payload).encode()
    req  = urllib.request.Request(
        ZABBIX_URL,
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
    except urllib.error.URLError as e:
        print(f"[X] Erro de conexão com Zabbix: {e}")
        sys.exit(1)

    if "error" in result:
        raise RuntimeError(f"Zabbix API erro: {result['error']}")
    return result["result"]


def wait_for_zabbix(max_wait: int = 120) -> None:
    print(f"[*] Aguardando Zabbix API em {ZABBIX_URL} ...")
    start = time.time()
    while time.time() - start < max_wait:
        try:
            zabbix_call(None, "apiinfo.version", {})
            print("[OK] Zabbix API respondendo.")
            return
        except Exception:
            time.sleep(5)
    print("[X] Zabbix API não respondeu após 120s. Verifique os containers.")
    sys.exit(1)


def login() -> str:
    version = zabbix_call(None, "apiinfo.version", {})
    print(f"[OK] Zabbix API versão {version}")

    # Zabbix 7.0 usa user.login com username (não user)
    try:
        token = zabbix_call(None, "user.login", {
            "username": ZABBIX_USER,
            "password": ZABBIX_PASS,
        })
    except RuntimeError:
        # fallback para versões mais antigas
        token = zabbix_call(None, "user.login", {
            "user": ZABBIX_USER,
            "password": ZABBIX_PASS,
        })
    print(f"[OK] Login bem-sucedido como {ZABBIX_USER}")
    return token


def ensure_group(sid: str, name: str) -> str:
    existing = zabbix_call(sid, "hostgroup.get", {
        "output": ["groupid", "name"],
        "filter": {"name": [name]},
    })
    if existing:
        return existing[0]["groupid"]

    created = zabbix_call(sid, "hostgroup.create", {"name": name})
    gid = created["groupids"][0]
    print(f"  [+] Grupo criado: {name} (id={gid})")
    return gid


def resolve_template_ids(sid: str, names: list[str]) -> list[str]:
    found = zabbix_call(sid, "template.get", {
        "output": ["templateid", "name"],
        "filter": {"name": names},
    })
    found_names = {t["name"] for t in found}
    for n in names:
        if n not in found_names:
            print(f"  [!] Template não encontrado no Zabbix: '{n}' — importe-o antes ou ajuste o nome.")
    return [t["templateid"] for t in found]


def host_exists(sid: str, hostname: str) -> str | None:
    result = zabbix_call(sid, "host.get", {
        "output": ["hostid"],
        "filter": {"host": [hostname]},
    })
    return result[0]["hostid"] if result else None


def add_host(sid: str, hostname: str, cfg: dict) -> None:
    print(f"\n[*] Processando host: {hostname}")

    # Grupos
    group_ids = [{"groupid": ensure_group(sid, g)} for g in cfg["groups"]]

    # Templates
    tpl_ids = resolve_template_ids(sid, cfg["templates"])
    templates = [{"templateid": tid} for tid in tpl_ids]

    # Interface SNMP v2c
    snmp_interface = {
        "type": 2,           # SNMP
        "main": 1,
        "useip": 1,
        "ip": cfg["ip"],
        "dns": "",
        "port": "161",
        "details": {
            "version": 2,    # SNMPv2c
            "bulk": 1,
            "community": SNMP_COMMUNITY,
        },
    }

    existing_id = host_exists(sid, hostname)

    if existing_id:
        print(f"  [~] Host já existe (id={existing_id}) — atualizando...")
        zabbix_call(sid, "host.update", {
            "hostid": existing_id,
            "status": 0,
            "description": cfg["description"],
            "groups": group_ids,
            "templates": templates,
            "tags": cfg["tags"],
            "inventory_mode": 1,
        })
        print(f"  [OK] {hostname} atualizado.")
    else:
        result = zabbix_call(sid, "host.create", {
            "host": hostname,
            "name": hostname,
            "description": cfg["description"],
            "status": 0,
            "interfaces": [snmp_interface],
            "groups": group_ids,
            "templates": templates,
            "tags": cfg["tags"],
            "inventory_mode": 1,
            "inventory": {
                "location": "TDAM01",
            },
        })
        hid = result["hostids"][0]
        print(f"  [OK] {hostname} criado com sucesso (hostid={hid}).")
        print(f"       IP de gerência: {cfg['ip']}")
        print(f"       SNMP community: {SNMP_COMMUNITY}")
        print(f"       Templates:      {cfg['templates']}")


def configure_snmp_trapper(sid: str) -> None:
    """Verifica se a action de SNMP trap está ativa."""
    print("\n[*] Verificando media types e actions de SNMP trap...")
    # Apenas informativo — configuração completa via UI
    print("  [i] Configure SNMP trap receiver no Zabbix UI se necessário.")


def print_summary() -> None:
    print("\n" + "=" * 60)
    print("  TDAM01 — Hosts cadastrados no Zabbix")
    print("=" * 60)
    for hostname, cfg in HOSTS.items():
        print(f"\n  {hostname}")
        print(f"    IP     : {cfg['ip']}")
        print(f"    Grupos : {', '.join(cfg['groups'])}")
        print(f"    Tags   : {', '.join(t['tag']+'='+t['value'] for t in cfg['tags'])}")

    print("\n" + "=" * 60)
    print("  Próximos passos:")
    print("  1. Acesse http://192.168.0.100:8080 (Admin/zabbix)")
    print("  2. Configuration > Hosts — verifique o status SNMP (verde)")
    print("  3. Ative o plugin Zabbix no Grafana:")
    print("     Grafana > Plugins > Zabbix > Enable")
    print("=" * 60)


def main() -> None:
    print("=" * 60)
    print("  TDAM01 — Cadastro de Hosts Zabbix via API")
    print("=" * 60)

    wait_for_zabbix()
    sid = login()

    for hostname, cfg in HOSTS.items():
        add_host(sid, hostname, cfg)

    configure_snmp_trapper(sid)

    zabbix_call(sid, "user.logout", {})
    print("\n[OK] Logout do Zabbix API.")

    print_summary()


if __name__ == "__main__":
    main()
