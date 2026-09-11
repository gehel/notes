# Two fixes from reviewing today's firewall log (home/network/logs/):
#
# 1. 953 of 981 log lines (97%) are the ceiling fan (192.168.30.63) retrying
#    its cloud phone-home every ~2s against iot2internet's deny-by-default --
#    correctly blocked, but dominating the log buffer (README.md already
#    flags this as a risk: the buffer is small and rotates). Silences this
#    one known, expected, harmless source with a no-log drop ahead of the
#    general logged catch-all -- still blocked, just not logged. Same
#    treatment already applied once before to a different rule (finding 7).
#
# 2. Pi-hole repeatedly (every ~10min) tries and fails to reach public IPv6
#    DNS resolvers (Cloudflare/Google/OpenDNS) for its own upstream queries,
#    blocked by services2internet's HTTP/HTTPS-only policy from finding 21
#    phase 2. Adds the missing exception, mirroring Pi-hole's existing IPv4
#    one (firewall.md rules 46-48: UDP/TCP 53, TCP 853 DoT) via a new
#    pihole-v6 address-list, EUI-64-pinned the same way as ha-v6/
#    octoprint-v6 -- same caveats apply (depends on privacy extensions
#    staying off, depends on the delegated prefix not changing again).
#    Computed from B8:27:EB:83:79:48 + vlan-services' current
#    2a02:1210:7621:9a41::/64 = 2a02:1210:7621:9a41:ba27:ebff:fe83:7948.
#
# Idempotent: safe to import more than once.
#
#   import log-review-fixes.rsc

:put "--- before ---"
/ip/firewall/filter/print detail where chain=iot2internet
/ipv6/firewall/address-list/print where list=pihole-v6
/ipv6/firewall/filter/print detail where chain=services2internet

# --- 1. silence the ceiling fan's expected iot2internet noise ---
:if ([:len [/ip/firewall/filter/find where chain=iot2internet and comment="iot2internet: ceiling fan phone-home (silenced, expected)"]] = 0) do={
    /ip/firewall/filter/add chain=iot2internet action=drop src-address=192.168.30.63 \
        comment="iot2internet: ceiling fan phone-home (silenced, expected)" \
        place-before=[find where chain=iot2internet and comment="iot2internet: deny everything else"]
    :put "added: ceiling fan silent drop"
} else={
    :put "already present: ceiling fan silent drop"
}

# --- 2. Pi-hole's own upstream DNS over IPv6 ---
:local piholeV6addr "2a02:1210:7621:9a41:ba27:ebff:fe83:7948"
:if ([:len [/ipv6/firewall/address-list/find where list=pihole-v6 and address=$piholeV6addr]] = 0) do={
    /ipv6/firewall/address-list/add list=pihole-v6 address=$piholeV6addr comment="Pi-hole, EUI-64 from B8:27:EB:83:79:48"
    :put "added: pihole-v6 address-list entry"
} else={
    :put "already present: pihole-v6 address-list entry"
}

:local anchor [/ipv6/firewall/filter/find where chain=services2internet and comment="services2internet: deny everything else"]

:if ([:len [/ipv6/firewall/filter/find where chain=services2internet and comment="services2internet: Pi-hole's own upstream DNS"]] = 0) do={
    /ipv6/firewall/filter/add chain=services2internet action=accept connection-state=new \
        protocol=udp src-address-list=pihole-v6 dst-port=53 \
        comment="services2internet: Pi-hole's own upstream DNS" place-before=$anchor
    :put "added: pihole-v6 DNS (udp)"
} else={
    :put "already present: pihole-v6 DNS (udp)"
}
:if ([:len [/ipv6/firewall/filter/find where chain=services2internet and comment="services2internet: Pi-hole's own upstream DNS (TCP)"]] = 0) do={
    /ipv6/firewall/filter/add chain=services2internet action=accept connection-state=new \
        protocol=tcp src-address-list=pihole-v6 dst-port=53 \
        comment="services2internet: Pi-hole's own upstream DNS (TCP)" place-before=$anchor
    :put "added: pihole-v6 DNS (tcp)"
} else={
    :put "already present: pihole-v6 DNS (tcp)"
}
:if ([:len [/ipv6/firewall/filter/find where chain=services2internet and comment="services2internet: Pi-hole's own upstream DNS-over-TLS"]] = 0) do={
    /ipv6/firewall/filter/add chain=services2internet action=accept connection-state=new \
        protocol=tcp src-address-list=pihole-v6 dst-port=853 \
        comment="services2internet: Pi-hole's own upstream DNS-over-TLS" place-before=$anchor
    :put "added: pihole-v6 DoT"
} else={
    :put "already present: pihole-v6 DoT"
}

:put "--- after ---"
/ip/firewall/filter/print detail where chain=iot2internet
/ipv6/firewall/address-list/print where list=pihole-v6
/ipv6/firewall/filter/print detail where chain=services2internet
