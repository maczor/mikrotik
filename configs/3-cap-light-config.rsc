# =============================================================================
# cAP ax — Solej Hotel (access point)
# Rola: bridge + WiFi przez CAPsMAN (zarządzane z hAP)
# RouterOS: 7.21.4+
#
# UWAGA: Ten skrypt jest IDENTYCZNY dla obu cAP-ów (piętro 1 i 2).
# Różni się tylko identity — popraw przed importem na każdym z osobna.
#
# PRZED IMPORTEM:
#   1. Reset to defaults BEZ default config (System -> Reset Configuration ->
#      "No Default Configuration").
#   2. Update firmware do 7.21.4 + RouterBOOT.
#   3. Podłącz cAP do hAP (ether1 cAP -> ether2 hAP dla pietra 1,
#                        ether1 cAP -> ether3 hAP dla pietra 2).
#      Zasilanie z PoE injectora cAP (jest w zestawie).
#   4. Podmień placeholdery:
#        __PLACEHOLDER_IDENTITY__       -> "cap-pietro1" lub "cap-pietro2"
#        __PLACEHOLDER_ADMIN_PASSWORD__ -> hasło admina
#
# IMPORT:
#   /import file-name=3-cap-light-config.rsc verbose=yes
#
# PO IMPORCIE:
#   - cAP dostanie IP od hAP w sieci 10.20.10.0/24 (mgmt VLAN).
#   - Sprawdź na hAP: /interface wifi capsman remote-cap print
#     -> powinien pokazać tego cAP-a jako "running".
# =============================================================================

:log info "cAP-Solej: start konfiguracji"

# --- Identity i hasło --------------------------------------------------------
/system identity set name="__PLACEHOLDER_IDENTITY__"
/system clock set time-zone-name=Europe/Warsaw
/user set [find name="admin"] password="__PLACEHOLDER_ADMIN_PASSWORD__"

# --- Bridge główny -----------------------------------------------------------
:if ([:len [/interface bridge find where name="bridge"]] = 0) do={
    /interface bridge add name="bridge" vlan-filtering=no \
        comment="Solej cAP bridge"
}

# --- Bridge ports (ether1 = uplink trunk, ether2 = access VLAN 20 opcjonalnie)
# Czyścimy ether1/ether2 z DOWOLNEGO bridge'a (default config / re-import na running),
# bo `add` wywala się gdy port jest już w innym bridge.
:foreach iface in={"ether1";"ether2"} do={
    :foreach bp in=[/interface bridge port find where interface=$iface] do={
        /interface bridge port remove $bp
    }
}
/interface bridge port add bridge=bridge interface=ether1 pvid=10 \
    comment="solej-mgr: trunk uplink (mgmt VLAN 10 native)"
/interface bridge port add bridge=bridge interface=ether2 pvid=20 \
    frame-types=admit-only-untagged-and-priority-tagged \
    comment="solej-mgr: access VLAN 20 -> TV/PS5 w pokoju"

# --- Bridge VLAN table -------------------------------------------------------
/interface bridge vlan remove [find where comment~"solej-mgr"]
/interface bridge vlan add bridge=bridge vlan-ids=10 \
    tagged=bridge untagged=ether1 \
    comment="solej-mgr: VLAN 10 mgmt native"
/interface bridge vlan add bridge=bridge vlan-ids=20 \
    tagged=bridge,ether1 untagged=ether2 \
    comment="solej-mgr: VLAN 20 priv"
/interface bridge vlan add bridge=bridge vlan-ids=30 \
    tagged=bridge,ether1 \
    comment="solej-mgr: VLAN 30 cams"
/interface bridge vlan add bridge=bridge vlan-ids=40 \
    tagged=bridge,ether1 \
    comment="solej-mgr: VLAN 40 guest"

# --- VLAN interface dla mgmt (żeby cAP dostał IP) ---------------------------
:if ([:len [/interface vlan find where name="vlan-mgmt"]] = 0) do={
    /interface vlan add name="vlan-mgmt" vlan-id=10 interface=bridge
}

# --- DHCP client na vlan-mgmt (IP z hAP) ------------------------------------
# Czyścimy tylko nasz wpis (po interface) — nie wszystkie, gdyby user miał coś własnego
/ip dhcp-client remove [find where interface=vlan-mgmt]
/ip dhcp-client add interface=vlan-mgmt disabled=no \
    use-peer-dns=yes use-peer-ntp=yes \
    comment="mgmt IP z hAP"

# --- Bridge VLAN filtering ON (na końcu konfiguracji bridge) ----------------
/interface bridge set [find name=bridge] vlan-filtering=yes

# --- WiFi: tryb CAP managed przez CAPsMAN -----------------------------------
# CAPsMAN na hAP wykryje tego cAP-a po manager=capsman + auto-discovery
# i automatycznie wyśle konfigurację (3 SSID-y x 2 pasma).
:foreach w in=[/interface wifi find] do={
    /interface wifi set $w configuration.manager=capsman disabled=no
}
# Włącz auto-discovery CAPsMAN po bridge (mgmt VLAN)
/interface wifi cap set enabled=yes \
    discovery-interfaces=vlan-mgmt \
    slaves-datapath=bridge \
    slaves-static=no

# --- Interface lists ---------------------------------------------------------
:if ([:len [/interface list find where name="MGMT"]] = 0) do={
    /interface list add name="MGMT"
}
:if ([:len [/interface list member find where list="MGMT" and interface="vlan-mgmt"]] = 0) do={
    /interface list member add list="MGMT" interface=vlan-mgmt
}

# --- Firewall (cAP nie routuje, ale chronimy input) -------------------------
/ip firewall filter remove [find where comment~"solej-mgr"]
/ip firewall filter add chain=input action=accept connection-state=established,related,untracked \
    comment="solej-mgr: established"
/ip firewall filter add chain=input action=drop connection-state=invalid \
    comment="solej-mgr: invalid"
/ip firewall filter add chain=input action=accept protocol=icmp limit=10,5:packet \
    comment="solej-mgr: icmp"
/ip firewall filter add chain=input action=accept in-interface-list=MGMT \
    comment="solej-mgr: admin tylko z mgmt VLAN"
/ip firewall filter add chain=input action=drop comment="solej-mgr: drop everything else"

# --- Disable nieużywane usługi ----------------------------------------------
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set www-ssl disabled=yes
/ip service set winbox disabled=no
/ip service set ssh disabled=no port=22

/tool mac-server set allowed-interface-list="MGMT"
/tool mac-server mac-winbox set allowed-interface-list="MGMT"
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list="MGMT"
/tool bandwidth-server set enabled=no
/tool romon set enabled=no
/ipv6 settings set disable-ipv6=yes
/ip cloud set ddns-enabled=no

:log info "cAP-Solej: konfiguracja zakończona"
:put "OK. Sprawdź na hAP: /interface wifi capsman remote-cap print"
