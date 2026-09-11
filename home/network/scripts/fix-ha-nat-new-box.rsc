# Fixes Home Assistant's remote HTTPS access, broken by the Swisscom box
# swap (2026-09-11): the new box hands mikrotik1 a WAN address in
# 192.168.1.0/24, not the old box's 10.1.1.0/24, so the dst-nat rule --
# hardcoded to dst-address=10.1.1.101 -- now matches nothing.
#
# The paired forward-chain rule (chain=internet2services, comment
# "internet2services: Home Assistant HTTPS") is NOT affected and is not
# touched here: it matches on dst-address=192.168.20.60 (HA's real internal
# address) plus connection-nat-state=dstnat, never on the WAN IP.
#
# Fix: drop dst-address= from the dst-nat rule entirely, matching only on
# in-interface-list=WAN protocol=tcp dst-port=443. Nothing else could
# legitimately arrive addressed elsewhere through this device's WAN side, so
# this is no looser in practice -- and it survives any future WAN IP change
# (a DHCP renewal, or another box swap) without needing to be touched again.
#
# Idempotent: safe to import more than once.
#
#   import fix-ha-nat-new-box.rsc

:put "--- before ---"
/ip firewall nat print detail where comment="Home Assistant - HTTPS"

:local natRule [/ip firewall nat find where comment="Home Assistant - HTTPS"]
:if ([:len $natRule] = 0) do={
    :error "could not find the 'Home Assistant - HTTPS' dst-nat rule -- check the comment"
}
:if ([:len [/ip firewall nat get $natRule dst-address]] > 0) do={
    # dst-address="" doesn't work for an IP-address-typed property ("value of
    # range expects range of ip addresses") -- needs !property, paired with
    # another real assignment in the same /set (see README.md's hard-won
    # lessons). Re-asserting in-interface-list=WAN to its own current value
    # is the harmless second assignment.
    /ip firewall nat set $natRule !dst-address in-interface-list=WAN
    :put "fixed: dst-address cleared"
} else={
    :put "already fixed: dst-address already empty"
}

:put "--- after ---"
/ip firewall nat print detail where comment="Home Assistant - HTTPS"
