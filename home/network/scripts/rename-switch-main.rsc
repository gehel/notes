# rename-switch-main.rsc -- mikrotik2 (CRS125) becomes "switch-main".
#
# Run on mikrotik2 (router2.home.ledcom.fr), 2026-10-20 config review.
# Idempotent: safe to import again. Blocks that use :local are wrapped in
# { } so that the value persists to the next line. Renaming an interface does not bounce its
# link, and RouterOS updates every reference (bridge ports, VLAN table,
# interface lists, CAP) by itself.
#
# The CAP may re-join the router's CAPsMAN after the identity change. Wifi
# clients then re-associate. Afterwards, check that IotaWatt (A8:48:FA:F2:40:4D)
# is back in the router's /caps-man/registration-table. If not, power-cycle it.
#
#   /import rename-switch-main.rsc verbose=yes dry-run
#   /import rename-switch-main.rsc verbose=yes
#
# Delete this file once it has run and the changes are verified.

/system/identity/set name=switch-main

# 1. RouterOS 6-era port names (ether1-gateway, etherN-master/slave-local,
#    sfp1-gateway) back to the default names.
:foreach id in=[/interface/ethernet/find] do={
    :local dn [/interface/ethernet/get $id default-name]
    :if ([/interface/ethernet/get $id name] != $dn) do={ /interface/ethernet/set $id name=$dn }
}

# 2. Comments on the ports that carry something.
/interface/ethernet/set [find where default-name=ether1] comment="trunk to router ether2"
/interface/ethernet/set [find where default-name=ether12] comment="trunk to switch-livingroom ether1"
/interface/ethernet/set [find where default-name=ether16] comment="trunk to switch-office ether1"
/interface/ethernet/set [find where default-name=ether21] comment="Home Assistant (services)"
/interface/ethernet/set [find where default-name=ether23] comment="Pi-hole (services)"
/interface/ethernet/set [find where default-name=ether24] comment="OctoPrint wired (iot)"

# 3. Leftovers: the one-shot trunk script from the switch-livingroom build, the
#    disabled factory DHCP client, the factory "router" DNS name.
/system/script/remove [find where name=mikrotik5-uplink-trunk]
/ip/dhcp-client/remove [find where comment="default configuration"]
/ip/dns/static/remove [find where name=router]

# 4. Comments: one naming scheme for every device.
/ip/firewall/filter/set [find where comment="HA API access (post-renumber)"] comment="HA API access"
{
:local names {"192.168.10.1"="router";"192.168.10.2"="switch-main";"192.168.10.3"="switch-office";"192.168.10.4"="ap-main";"192.168.10.5"="switch-livingroom";"192.168.10.6"="router, staging address (remove after the rollback week)";"192.168.10.90"="desktop";"192.168.10.92"="gimli, work laptop";"192.168.50.2"="phone (MrG Galaxy S24), via wireguard1"}
:foreach id in=[/ip/firewall/address-list/find where list=mgmt] do={
    :local a [:tostr [/ip/firewall/address-list/get $id address]]
    :if ([:typeof ($names->$a)] != "nothing") do={
        /ip/firewall/address-list/set $id comment=($names->$a)
    }
}
}

:put "rename-switch-main: done. Check the prints below."
/system/identity/print
/interface/ethernet/print
/interface/bridge/vlan/print detail where dynamic=no
/system/script/print
/ip/dhcp-client/print
/ip/dns/static/print
/ip/firewall/address-list/print
/ip/firewall/filter/print
