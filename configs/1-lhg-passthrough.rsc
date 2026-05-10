# =============================================================================
# LHG LTE18 — Solej Hotel
# Rola: modem LTE w trybie passthrough (bez routingu, IP idzie do hAP)
# RouterOS: 7.20.8+
#
# PRZED IMPORTEM:
#   1. Reset to defaults BEZ default config (System -> Reset Configuration ->
#      "No Default Configuration" zaznaczone).
#   2. Włóż kartę SIM (T-Mobile).
#   3. Podłącz LHG przez kabel ethernet do laptopa (zasilanie z PoE injectora
#      LHG lub tymczasowo hAP).
#   4. WinBox po MAC. Zaktualizuj firmware do RouterOS 7.20.8 + RouterBOOT.
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
#   /interface lte monitor [find] once
#   -> status: running, signal RSRP > -90 dBm, SINR > 5 dB
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

# --- APN profile (passthrough zdefiniowany, ALE jeszcze nie aktywowany) -----
# UWAGA w 7.20.8: passthrough-interface/passthrough-mac są atrybutami
# APN PROFILU, nie /interface lte (jak w starszych wydaniach RouterOS).
# Modem oddaje publiczne IP od operatora prosto na ether1, do MAC hAP.
# Bez double-NAT, bez routingu na LHG.
#
# UWAGA #2: aktywację `apn-profiles=solej-apn` robimy DOPIERO NA KOŃCU
# skryptu (sekcja "Aktywacja LTE passthrough"). Przedwczesna aktywacja
# odcięłaby MAC-Winbox z laptopa zanim firewall/hardening dolecą.
:if ([:len [/interface lte apn find where name="solej-apn"]] = 0) do={
    /interface lte apn add name="solej-apn" apn="__PLACEHOLDER_APN__" \
        use-peer-dns=yes \
        passthrough-interface=ether1 \
        passthrough-mac="__PLACEHOLDER_HAP_ETHER1_MAC__"
}

# --- LTE passthrough = LHG nie ma własnego IP -------------------------------
# W trybie passthrough LHG przekazuje publiczne IP od operatora bezpośrednio
# do MAC hAP-a przez ether1. LHG SAM nie ma żadnego IP — zarządzanie odbywa
# się WYŁĄCZNIE przez MAC-Winbox po ether1.
#
# Dlaczego nie ma service-mode IP (192.168.99.1/24 + DHCP):
# Próbowaliśmy. W 7.20.8 jednoczesny passthrough + service-IP/DHCP na ether1
# powoduje konflikt — passthrough wygrywa losowo, service-mode dropuje ramki
# z obcego MAC-a (laptop), a MAC-Winbox traci synchronizację. Efekt: po
# pierwszym aktywowaniu passthrough laptop traci dostęp i jedynym ratunkiem
# jest reset przyciskiem.
#
# Service mode (laptop bezpośrednio do LHG): podłącz laptop, połącz po
# MAC-Winbox (Neighbors → klik MAC LHG, bez IP), pracuj. Jak chcesz IP —
# tymczasowo dodaj sobie ręcznie:
#   /ip address add address=192.168.99.1/24 interface=ether1
# i zdejmij po skończeniu serwisu.

# --- Wyłącz wifi (LHG ma slot wifi, ale my go nie używamy) -------------------
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

# --- Firewall (LHG nie routuje, zabezpieczamy tylko input) ------------------
# W passthrough LHG SAM nie ma IP, więc input chain dotyczy tylko:
# - ramek MAC-management na ether1 (MAC-Winbox/Neighbors)
# - cellular (LTE backhaul) — tu nie ma własnego IP, więc input pusty
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
# UWAGA: w passthrough LHG nie ma IP, więc winbox/ssh po IP są bez znaczenia.
# Zostawiamy je włączone bez address-list — i tak są dostępne TYLKO przez
# MAC-Winbox (mac-server allowed-interface-list=mgmt poniżej). Gdyby admin
# tymczasowo nadał LHG IP w service-mode, IP-Winbox/SSH też zadziała.
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set www-ssl disabled=yes
/ip service set winbox disabled=no
/ip service set ssh disabled=no port=22

# --- Hardening ----------------------------------------------------------------
/tool mac-server set allowed-interface-list="mgmt"
/tool mac-server mac-winbox set allowed-interface-list="mgmt"
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list="mgmt"
/tool bandwidth-server set enabled=no
/tool romon set enabled=no
# UWAGA w 7.20.8: /ip cloud nie przyjmuje ddns-enabled=no/disable/disabled —
# tylko `auto` (default) lub `yes`. Na LHG bez SIM cloud i tak nie wstanie,
# więc `auto` jest funkcjonalnie OK. Wyłączamy tylko update-time.
/ip cloud set update-time=no

# --- LED na panelu LHG: pokazuj LTE signal ------------------------------------
# (działa na LHG LTE6/LTE18 — pokazuje siłę sygnału na LED)
# type=modem-signal pokazuje SIŁĘ sygnału (interface-status pokazuje tylko up/down).
:do {
    /system leds set [find leds="lte_signal1"] type=modem-signal interface=lte1
} on-error={
    :log info "LHG-Solej: LED config - pomijam"
}

# --- AKTYWACJA LTE PASSTHROUGH (na samym końcu, świadomie) ------------------
# Cała reszta konfiguracji (firewall, hardening, mac-server, mgmt list) jest
# już w miejscu. Teraz aktywujemy passthrough — od tego momentu LHG przekazuje
# publiczne IP do MAC hAP i przestaje odpowiadać innym MAC-om przez ether1
# poza ramkami MAC-management. MAC-Winbox z laptopa nadal działa, ale TYLKO
# bezpośrednio (bez IP) i tylko jeśli laptop wpięty BEZPOŚREDNIO do LHG
# (nie przez hAP).
/interface lte set [find] apn-profiles="solej-apn"

:log info "LHG-Solej: konfiguracja zakończona, passthrough aktywny"
:put "OK. LHG: skieruj antenę na BTS, sprawdź sygnał: /interface lte monitor [find] once"
:put "Dostęp do LHG: WYŁĄCZNIE MAC-Winbox po ether1 (nie przez hAP)"
