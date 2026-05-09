# =============================================================================
# LHG LTE18 — Solej Hotel
# Rola: modem LTE w trybie passthrough (bez routingu, IP idzie do hAP)
# RouterOS: 7.21.4+
#
# PRZED IMPORTEM:
#   1. Reset to defaults BEZ default config (System -> Reset Configuration ->
#      "No Default Configuration" zaznaczone).
#   2. Włóż kartę SIM (T-Mobile).
#   3. Podłącz LHG przez kabel ethernet do laptopa (zasilanie z PoE injectora
#      LHG lub tymczasowo hAP).
#   4. WinBox po MAC. Zaktualizuj firmware do RouterOS 7.21.4 + RouterBOOT.
#   5. Otwórz ten plik w edytorze i podmień placeholdery:
#        __PLACEHOLDER_ADMIN_PASSWORD__   -> hasło admina (min. 16 znaków)
#        __PLACEHOLDER_HAP_ETHER1_MAC__   -> MAC adres ether1 hAP ax3
#                                            (pobierz na hAP: /interface ethernet print)
#        __PLACEHOLDER_APN__              -> APN operatora (T-Mobile: "internet")
#   6. Wgraj plik do LHG (Files -> drag & drop).
#
# IMPORT:
#   /import file-name=1-lhg-passthrough.rsc verbose=yes
#
# WERYFIKACJA PO IMPORCIE:
#   /interface lte info [find] once
#   -> status: registered, signal: lepiej niż -90 dBm
#   /interface lte print
#   -> running=true
# =============================================================================

:log info "LHG-Solej: start konfiguracji"

# --- Identity i czas ----------------------------------------------------------
/system identity set name="lhg-solej-lte"
/system clock set time-zone-name=Europe/Warsaw
/system note set show-at-login=no note=""

# --- Hasło admina -------------------------------------------------------------
/user set [find name="admin"] password="__PLACEHOLDER_ADMIN_PASSWORD__"

# --- APN ----------------------------------------------------------------------
:if ([:len [/interface lte apn find where name="solej-apn"]] = 0) do={
    /interface lte apn add name="solej-apn" apn="__PLACEHOLDER_APN__" use-peer-dns=yes
}

# --- LTE: passthrough mode ----------------------------------------------------
# Modem oddaje publiczne IP od operatora prosto na ether1, do MAC hAP.
# Bez double-NAT, bez routingu na LHG.
/interface lte set [find] \
    apn-profiles="solej-apn" \
    passthrough-interface=ether1 \
    passthrough-mac="__PLACEHOLDER_HAP_ETHER1_MAC__"

# --- Lokalny IP na ether1 -----------------------------------------------------
# UWAGA: w trybie LTE passthrough ramki idą bezpośrednio do MAC hAP (omijają stos IP).
# Ten lokalny IP/DHCP/firewall działa TYLKO gdy LHG jest podpięty bezpośrednio do
# laptopa (kabel serwisowy, hAP odłączony). Gdy LHG jedzie w trybie produkcyjnym
# (passthrough do hAP), te wpisy są niefunkcjonalne — to OK, zostają jako
# "service mode access", aktywują się gdy odepniesz hAP.
# 192.168.99.0/24 nie koliduje z 10.20.x.x sieci hotelu.
:if ([:len [/ip address find where address="192.168.99.1/24"]] = 0) do={
    /ip address add address=192.168.99.1/24 interface=ether1 comment="solej-mgr: LHG service LAN"
}

# DHCP dla serwisowego laptopa
:if ([:len [/ip pool find where name="lhg-service"]] = 0) do={
    /ip pool add name="lhg-service" ranges=192.168.99.100-192.168.99.199
}
:if ([:len [/ip dhcp-server find where name="lhg-service"]] = 0) do={
    /ip dhcp-server add name="lhg-service" interface=ether1 \
        address-pool="lhg-service" lease-time=10m disabled=no
}
:if ([:len [/ip dhcp-server network find where address="192.168.99.0/24"]] = 0) do={
    /ip dhcp-server network add address=192.168.99.0/24 \
        gateway=192.168.99.1 dns-server=192.168.99.1
}

# --- DNS server lokalny -------------------------------------------------------
/ip dns set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes

# --- WiFi (jeśli paczka aktywna) — wyłącz radio -------------------------------
:do {
    :foreach i in=[/interface wifi find] do={
        /interface wifi set $i disabled=yes
    }
} on-error={
    :log info "LHG-Solej: wifi package nieaktywny lub brak - pomijam"
}

# --- Interface lists ----------------------------------------------------------
:if ([:len [/interface list find where name="mgmt"]] = 0) do={
    /interface list add name="mgmt"
}
:if ([:len [/interface list member find where list="mgmt" and interface="ether1"]] = 0) do={
    /interface list member add interface=ether1 list="mgmt"
}

# --- Firewall (minimalny — LHG nie robi NAT) ----------------------------------
# Reguły taggowane "solej-mgr:" dla idempotentnego rebuild
/ip firewall filter remove [find where comment~"solej-mgr"]
/ip firewall filter add chain=input action=accept connection-state=established,related \
    comment="solej-mgr: established/related"
/ip firewall filter add chain=input action=drop connection-state=invalid \
    comment="solej-mgr: invalid"
/ip firewall filter add chain=input action=accept protocol=icmp limit=10,5:packet \
    comment="solej-mgr: icmp limited"
/ip firewall filter add chain=input action=accept in-interface=ether1 \
    comment="solej-mgr: admin z ether1 (kabel serwisowy)"
/ip firewall filter add chain=input action=drop comment="solej-mgr: drop everything else (LTE side)"

# --- Wyłącz nieużywane usługi -------------------------------------------------
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set www-ssl disabled=yes
/ip service set winbox disabled=no address=192.168.99.0/24
/ip service set ssh disabled=no address=192.168.99.0/24 port=22

# --- Hardening ----------------------------------------------------------------
/tool mac-server set allowed-interface-list="mgmt"
/tool mac-server mac-winbox set allowed-interface-list="mgmt"
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list="mgmt"
/tool bandwidth-server set enabled=no
/tool romon set enabled=no
/ip cloud set ddns-enabled=no update-time=no

# --- LED na panelu LHG: pokazuj LTE signal ------------------------------------
# (działa na LHG LTE6/LTE18 — pokazuje siłę sygnału na LED)
# type=modem-signal pokazuje SIŁĘ sygnału (interface-status pokazuje tylko up/down).
:do {
    /system leds set [find leds="lte_signal1"] type=modem-signal interface=lte1
} on-error={
    :log info "LHG-Solej: LED config - pomijam"
}

:log info "LHG-Solej: konfiguracja zakończona"
:put "OK. LHG: skieruj antenę na BTS, potem na hAP: /interface lte info once"
