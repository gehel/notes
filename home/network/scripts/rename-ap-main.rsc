# rename-ap-main.rsc -- mikrotik4 (cAP XL ac) becomes "ap-main".
#
# Run on mikrotik4 (router4.home.ledcom.fr), 2026-10-20 config review.
# Idempotent: safe to import again. Blocks that use :local are wrapped in
# { } so that the value persists to the next line. Standalone AP: the identity is not used by
# the wifi configuration, so clients are not affected.
#
#   /import rename-ap-main.rsc verbose=yes dry-run
#   /import rename-ap-main.rsc verbose=yes
#
# Delete this file once it has run and the changes are verified.

/system/identity/set name=ap-main

/interface/ethernet/set [find where default-name=ether1] comment="uplink to router ether3, PoE"

# Comments: one naming scheme for every device.
{
:local names {"192.168.10.1"="router";"192.168.10.2"="switch-main";"192.168.10.3"="switch-office";"192.168.10.4"="ap-main";"192.168.10.5"="switch-livingroom";"192.168.10.6"="router, staging address (remove after the rollback week)";"192.168.10.90"="desktop";"192.168.10.92"="gimli, work laptop";"192.168.50.2"="phone (MrG Galaxy S24), via wireguard1"}
:foreach id in=[/ip/firewall/address-list/find where list=mgmt] do={
    :local a [:tostr [/ip/firewall/address-list/get $id address]]
    :if ([:typeof ($names->$a)] != "nothing") do={
        /ip/firewall/address-list/set $id comment=($names->$a)
    }
}
}

:put "rename-ap-main: done. Check the prints below."
/system/identity/print
/interface/ethernet/print
/ip/firewall/address-list/print
