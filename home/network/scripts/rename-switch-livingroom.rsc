# rename-switch-livingroom.rsc -- mikrotik5 (hEX, living room) becomes
# "switch-livingroom", and loses the factory-default config that survived its
# build (finding S19).
#
# Run on mikrotik5 (router5.home.ledcom.fr), 2026-10-20 config review.
# Idempotent: safe to import again. Blocks that use :local are wrapped in
# { } so that the value persists to the next line. The management address 192.168.10.5 and its
# default route are not touched. 192.168.88.1 sits on the same bridge, but
# nothing uses it.
#
#   /import rename-switch-livingroom.rsc verbose=yes dry-run
#   /import rename-switch-livingroom.rsc verbose=yes
#
# Delete this file once it has run and the changes are verified.

/system/identity/set name=switch-livingroom

/interface/ethernet/set [find where default-name=ether1] comment="trunk to switch-main ether12"
/interface/ethernet/set [find where default-name=ether2] comment="TV (Samsung), wired"

# 1. Factory leftovers (S19).
#    - The defconf LAN address and its DNS name.
/ip/address/remove [find where address="192.168.88.1/24"]
/ip/dns/static/remove [find where name=router.lan]
#    - The DNS resolver. The input firewall already limits it to mgmt hosts,
#      but a switch has no reason to answer DNS.
/ip/dns/set allow-remote-requests=no
#    - Media and SMB sharing of any disk plugged into the USB port.
/disk/settings/set auto-media-sharing=no auto-smb-sharing=no
#    - Router-style forward rules (ipsec, fasttrack, WAN). The bridge does not
#      use the IP firewall, so they never match. switch-office has none either.
/ip/firewall/filter/remove [find where chain=forward]
#    - The IPv6 firewall. IPv6 is disabled on this device.
/ipv6/firewall/filter/remove [find where dynamic=no]
/ipv6/firewall/address-list/remove [find where list=bad_ipv6]
#    - The WAN list. It is empty, and the rules above were its last users.
/interface/list/remove [find where name=WAN]

# 2. Comments: one naming scheme for every device.
{
:local names {"192.168.10.1"="router";"192.168.10.2"="switch-main";"192.168.10.3"="switch-office";"192.168.10.4"="ap-main";"192.168.10.5"="switch-livingroom";"192.168.10.6"="router, staging address (remove after the rollback week)";"192.168.10.90"="desktop";"192.168.10.92"="gimli, work laptop";"192.168.50.2"="phone (MrG Galaxy S24), via wireguard1"}
:foreach id in=[/ip/firewall/address-list/find where list=mgmt] do={
    :local a [:tostr [/ip/firewall/address-list/get $id address]]
    :if ([:typeof ($names->$a)] != "nothing") do={
        /ip/firewall/address-list/set $id comment=($names->$a)
    }
}
}

:put "rename-switch-livingroom: done. Check the prints below."
/system/identity/print
/interface/ethernet/print
/ip/address/print
/ip/dns/print
/ip/dns/static/print
/disk/settings/print
/ip/firewall/filter/print
/ipv6/firewall/filter/print
/interface/list/print
/ip/firewall/address-list/print
