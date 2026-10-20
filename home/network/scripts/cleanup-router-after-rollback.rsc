# cleanup-router-after-rollback.rsc -- end of the RB5009 rollback week.
#
# Run on router (mikrotik6) ONLY when the rollback option is given up, not
# before 2026-10-27, and only after mikrotik1 has been wiped (Phase 4).
# It removes what `rollback` needs: the cutover/rollback scripts and the
# "production, enabled by cutover" comments they match on. It also removes the
# staging address 192.168.10.6.
#
# Connect to router.home.ledcom.fr (192.168.10.1) for this, not to .10.6.
# Then, on switch-main, switch-office, ap-main and switch-livingroom:
#   /ip/firewall/address-list/remove [find where address=192.168.10.6]
# and delete the router6 record in Pi-hole.
#
#   /import cleanup-router-after-rollback.rsc verbose=yes dry-run
#   /import cleanup-router-after-rollback.rsc verbose=yes
#
# Delete this file once it has run and the changes are verified.

/system/script/remove [find where name=cutover]
/system/script/remove [find where name=rollback]

# Plain comments for the production addresses.
:foreach id in=[/ip/address/find where comment="production, enabled by cutover"] do={
    :local ifn [/ip/address/get $id interface]
    /ip/address/set $id comment=("gateway, " . $ifn)
}
:foreach id in=[/ipv6/address/find where comment="production, enabled by cutover"] do={
    :local ifn [/ipv6/address/get $id interface]
    /ipv6/address/set $id comment=("gateway, " . $ifn . ", from the delegated prefix")
}

# The staging address and its mgmt entry.
/ip/address/remove [find where address="192.168.10.6/24"]
/ip/firewall/address-list/remove [find where address=192.168.10.6]

:put "cleanup-router-after-rollback: done. Check the prints below."
/system/script/print
/ip/address/print
/ipv6/address/print
/ip/firewall/address-list/print where list=mgmt
