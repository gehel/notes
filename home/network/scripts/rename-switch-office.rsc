# rename-switch-office.rsc -- mikrotik3 (hEX, office) becomes "switch-office".
#
# Run on mikrotik3 (router3.home.ledcom.fr), 2026-10-20 config review.
# Idempotent: safe to import again. Blocks that use :local are wrapped in
# { } so that the value persists to the next line. Nothing here touches the management path.
#
#   /import rename-switch-office.rsc verbose=yes dry-run
#   /import rename-switch-office.rsc verbose=yes
#
# Delete this file once it has run and the changes are verified.

/system/identity/set name=switch-office

# 1. Comments on the trunk.
/interface/ethernet/set [find where default-name=ether1] comment="trunk to switch-main ether16"

# 2. Factory leftovers: the disabled DHCP client, the empty WAN list (S16 moved
#    ether1 out of it), and a CAP target on a device without wireless.
/ip/dhcp-client/remove [find where comment=defconf]
/interface/list/remove [find where name=WAN]
/interface/wireless/cap/set caps-man-addresses=""

# 3. Comments: one naming scheme for every device.
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

:put "rename-switch-office: done. Check the prints below."
/system/identity/print
/interface/ethernet/print
/interface/list/print
/interface/wireless/cap/print
/ip/dhcp-client/print
/ip/firewall/address-list/print
/ip/firewall/filter/print
