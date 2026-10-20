# rename-router.rsc -- mikrotik6 (RB5009) becomes "router".
#
# Run on mikrotik6 (router1/router6.home.ledcom.fr), 2026-10-20 config review.
# Idempotent: safe to import again. Blocks that use :local are wrapped in
# { } so that the value persists to the next line. Nothing here touches the management path,
# the address plan, or the rules that `cutover`/`rollback` depend on (the
# "production, enabled by cutover" comments stay until the rollback week ends,
# see cleanup-router-after-rollback.rsc).
#
#   /import rename-router.rsc verbose=yes dry-run
#   /import rename-router.rsc verbose=yes
#
# Delete this file once it has run and the changes are verified.

# 1. Identity. CAPsMAN interface names follow the CAP's identity, not this one.
/system/identity/set name=router

# 2. Comments that still name the old devices or the migration.
/interface/bridge/set [find where name=bridge-main] comment="LAN"
/interface/list/set [find where name=WAN] comment="WAN-facing interface(s), referenced by the firewall and NAT"
:foreach id in=[/interface/bridge/port/find where dynamic=no] do={
    :local ifn [/interface/bridge/port/get $id interface]
    :if ($ifn = "ether2") do={ /interface/bridge/port/set $id comment="trunk to switch-main ether1" }
    :if ($ifn = "ether3") do={ /interface/bridge/port/set $id comment="ap-main (cAP XL ac), PoE" }
}
/ip/firewall/filter/set [find where comment="HA API access (post-renumber)"] comment="HA API access"

# 3. The "dropped" log-prefix has no effect without log=yes.
/ip/firewall/filter/set [find where comment="Drop all other forward traffic"] log-prefix=""

# 4. Address lists: one naming scheme for every device.
{
:local names {"192.168.10.1"="router";"192.168.10.2"="switch-main";"192.168.10.3"="switch-office";"192.168.10.4"="ap-main";"192.168.10.5"="switch-livingroom";"192.168.10.6"="router, staging address (remove after the rollback week)";"192.168.10.90"="desktop";"192.168.10.92"="gimli, work laptop";"192.168.50.2"="phone (MrG Galaxy S24), via wireguard1"}
:foreach id in=[/ip/firewall/address-list/find where dynamic=no] do={
    :local l [/ip/firewall/address-list/get $id list]
    :if ($l = "mgmt" || $l = "ha-mikrotik-targets") do={
        :local a [:tostr [/ip/firewall/address-list/get $id address]]
        :if ([:typeof ($names->$a)] != "nothing") do={
            /ip/firewall/address-list/set $id comment=($names->$a)
        }
    }
}
}

# 5. VLAN 30 on ether3: ap-main serves LEDCOM only (no IoT SSID), so nothing uses it.
/interface/bridge/vlan/set [find where vlan-ids=30] tagged=bridge-main,ether2

# 6. CAPsMAN channel ch6 is not used by any configuration.
/caps-man/channel/remove [find where name=ch6]

# 7. DHCP reservations. switch-office and ap-main have static addresses outside
#    the pool, so their reservations do nothing. Name the unnamed ones.
/ip/dhcp-server/lease/remove [find where address=192.168.10.3]
/ip/dhcp-server/lease/remove [find where address=192.168.10.4]
/ip/dhcp-server/lease/set [find where address=192.168.10.90] comment="desktop"
/ip/dhcp-server/lease/set [find where address=192.168.10.92] comment="gimli, work laptop"
/ip/dhcp-server/lease/set [find where address=192.168.10.50] comment="TV (Samsung), wired to switch-livingroom ether2"

# 8. Static "router" DNS name: a factory leftover. Clients use Pi-hole.
/ip/dns/static/remove [find where name=router]

# 9. Finding 37: two lease events for one host can race. The second one then
#    fails on "remove" and stops before it adds the DNS entry. Ignore that error.
{
:local ls ":if ([:len \$\"lease-hostname\"] > 0) do={\n  :local dnsName (\$\"lease-hostname\" . \".home.ledcom.fr\")\n  :do { /ip/dns/static/remove [find where name=\$dnsName] } on-error={}\n  :if (\$leaseBound = 1) do={\n    :do {\n      /ip/dns/static/add name=\$dnsName address=\$leaseActIP type=A ttl=5m comment=\"dhcp-to-dns: \$leaseServerName\"\n    } on-error={\n      :log warning \"dhcp-to-dns: failed to add DNS entry for \$dnsName (\$leaseActIP)\"\n    }\n  }\n}\n"
:foreach id in=[/ip/dhcp-server/find] do={ /ip/dhcp-server/set $id lease-script=$ls }
}

:put "rename-router: done. Check the prints below."
/system/identity/print
/interface/bridge/port/print
/interface/bridge/vlan/print
/ip/firewall/address-list/print where list=mgmt
/ip/firewall/address-list/print where list=ha-mikrotik-targets
/ip/dhcp-server/lease/print
/caps-man/channel/print
/ip/dns/static/print
