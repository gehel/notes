# Reverts the port-8443 workaround from earlier today: the real cause of
# the external-access timeout turned out to be a stale DNS record
# (home.ledcom.fr still pointing at the box's old public IP after another
# ISP-side change), not the port-443 conflict with the box's own admin UI
# that was suspected in between. Moving back to the standard port now that
# the actual cause is understood and being fixed at the DNS level instead.
#
# Idempotent: safe to import more than once.
#
#   import revert-ha-nat-port-443.rsc

:put "--- before ---"
/ip/firewall/nat/print detail where comment="Home Assistant - HTTPS"

:local natRule [/ip/firewall/nat/find where comment="Home Assistant - HTTPS"]
:if ([:len $natRule] = 0) do={
    :error "could not find the 'Home Assistant - HTTPS' dst-nat rule -- check the comment"
}
:if ([/ip/firewall/nat/get $natRule dst-port] != "443") do={
    /ip/firewall/nat/set $natRule dst-port=443
    :put "reverted: dst-port back to 443"
} else={
    :put "already reverted: dst-port already 443"
}

:put "--- after ---"
/ip/firewall/nat/print detail where comment="Home Assistant - HTTPS"
