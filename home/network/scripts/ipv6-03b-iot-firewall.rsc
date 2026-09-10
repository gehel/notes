# Finding 21, phase 3 of 3, step b: firewall for vlan-iot now that its IPv6
# /64 is known from step a's output (2a02:1210:680f:c40e::/64).
#
# Deliberately minimal, matching this phase's framing (most devices here
# don't speak IPv6 at all): one dispatch chain, iot2internet, deny by
# default with a named exception for OctoPrint (mirrors its existing IPv4
# "octoprint" address-list exception). No iot2services/iot2users chains --
# nothing on this VLAN needs IPv6 access to either today, so they fall
# through to the existing terminating "drop inbound from WAN" catch-all,
# same outcome as an explicit deny, just without a distinct log prefix.
# Router management over IPv6 stays closed, same reasoning as the other two
# VLANs -- no input-chain accept added.
#
# octoprint-v6 holds both of OctoPrint's known IPv6 addresses (wifi + wired,
# same two MACs as the IPv4 "octoprint" address-list), computed via EUI-64
# the same way as ha-v6 in phase 2 -- same two caveats apply (depends on
# privacy extensions staying off on that host, depends on Swisscom's
# delegated prefix not changing):
#   E4:5F:01:DA:22:96 (wifi)  + 2a02:1210:680f:c40e::/64
#     = 2a02:1210:680f:c40e:e65f:01ff:feda:2296
#   E4:5F:01:DA:22:95 (wired) + 2a02:1210:680f:c40e::/64
#     = 2a02:1210:680f:c40e:e65f:01ff:feda:2295
#
# Idempotent: safe to import more than once.
#
#   import ipv6-03b-iot-firewall.rsc

:put "--- before ---"
/ipv6/firewall/address-list print where list=octoprint-v6
/ipv6/firewall/filter print detail where chain~"iot" or chain=forward

:local octoWifi "2a02:1210:680f:c40e:e65f:01ff:feda:2296"
:local octoWired "2a02:1210:680f:c40e:e65f:01ff:feda:2295"

:if ([:len [/ipv6/firewall/address-list find where list=octoprint-v6 and address=$octoWifi]] = 0) do={
    /ipv6/firewall/address-list add list=octoprint-v6 address=$octoWifi \
        comment="OctoPrint wifi, EUI-64 from E4:5F:01:DA:22:96"
    :put "added: octoprint-v6 wifi entry"
} else={
    :put "already present: octoprint-v6 wifi entry"
}
:if ([:len [/ipv6/firewall/address-list find where list=octoprint-v6 and address=$octoWired]] = 0) do={
    /ipv6/firewall/address-list add list=octoprint-v6 address=$octoWired \
        comment="OctoPrint wired, EUI-64 from E4:5F:01:DA:22:95"
    :put "added: octoprint-v6 wired entry"
} else={
    :put "already present: octoprint-v6 wired entry"
}

# --- iot2internet: OctoPrint exception, then the wall ---
:if ([:len [/ipv6/firewall/filter find where chain=iot2internet and comment="iot2internet: octoprint updates"]] = 0) do={
    /ipv6/firewall/filter add chain=iot2internet action=accept connection-state=new \
        protocol=tcp dst-port=80,443 src-address-list=octoprint-v6 comment="iot2internet: octoprint updates"
    :put "added: iot2internet octoprint exception"
} else={
    :put "already present: iot2internet octoprint exception"
}
:if ([:len [/ipv6/firewall/filter find where chain=iot2internet and comment="iot2internet: deny everything else"]] = 0) do={
    /ipv6/firewall/filter add chain=iot2internet action=drop log=yes log-prefix="iot2internet-v6" \
        comment="iot2internet: deny everything else"
    :put "added: iot2internet catch-all drop"
} else={
    :put "already present: iot2internet catch-all drop"
}

# --- dispatch, anchored before the final catch-all ---
:if ([:len [/ipv6/firewall/filter find where chain=forward and comment="dispatch: iot -> internet"]] = 0) do={
    /ipv6/firewall/filter add chain=forward action=jump jump-target=iot2internet \
        in-interface=vlan-iot out-interface-list=WAN comment="dispatch: iot -> internet" \
        place-before=[find where chain=forward and comment="drop inbound from WAN"]
    :put "added: dispatch iot -> internet"
} else={
    :put "already present: dispatch iot -> internet"
}

:put "--- after ---"
/ipv6/firewall/address-list print where list=octoprint-v6
/ipv6/firewall/filter print detail where chain=forward or chain=iot2internet
