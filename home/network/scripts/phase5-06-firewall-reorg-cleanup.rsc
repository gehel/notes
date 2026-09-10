# Final step of the forward-chain reorg (see phase5-02, already applied and
# committed; phase5-03/04/05 added rules and tightened src-address scoping
# the reorg was missing, found by reviewing logs before running this).
# Removes the old individual rules now confirmed dead (every one
# of them is already unreachable - each destination for users/services/iot
# traffic is claimed by an earlier jump rule that always terminates in its
# sub-chain, verified against live /print output before this script was
# written), removes the now-unused "iot-internet" address list (superseded
# by "octoprint"), and points the remaining ether1 references at the new
# WAN interface list instead of the literal interface name.
#
# Every remove/set below matches on a single condition (a comment, or for
# the one uncommented NAT rule, its distinctive action) - never a combined
# condition, per this project's own history of find/remove being unreliable
# on ambiguous combined matches.
#
# Run on mikrotik1.

# --- dead forward-chain rules, superseded by the new jump-chains ---
/ip/firewall/filter/remove [find where comment="Home Assistant - HTTPS"]
/ip/firewall/filter/remove [find where comment="Home can connect everywhere (vlan-users)"]
/ip/firewall/filter/remove [find where comment="services: internet"]
/ip/firewall/filter/remove [find where comment="HA MikroTik integration: services -> users API"]
/ip/firewall/filter/remove [find where comment="ceiling fan: drop DNS (udp)"]
/ip/firewall/filter/remove [find where comment="ceiling fan: drop DNS (tcp)"]
/ip/firewall/filter/remove [find where comment="iot: DNS to pi-hole (udp)"]
/ip/firewall/filter/remove [find where comment="iot: DNS to pi-hole (tcp)"]
/ip/firewall/filter/remove [find where comment="HA -> Tuya local (fan)"]
/ip/firewall/filter/remove [find where comment="iot: MQTT to HA"]
/ip/firewall/filter/remove [find where comment="iot exception: octoprint updates"]
/ip/firewall/filter/remove [find where comment="HA -> Tasmota/IotaWatt"]
/ip/firewall/filter/remove [find where comment="iot: deny everything else"]
/ip/firewall/filter/remove [find where comment="HA -> ESPHome (IotaWatt)"]
/ip/firewall/filter/remove [find where comment="services: no users"]
/ip/firewall/filter/remove [find where comment="mgmt hosts: full"]
/ip/firewall/filter/remove [find where comment="users: DNS"]
/ip/firewall/filter/remove [find where comment="users: HA web"]
/ip/firewall/filter/remove [find where comment="users2services"]
/ip/firewall/filter/remove [find where comment="mgmt hosts: iot"]
/ip/firewall/filter/remove [find where comment="users2iot"]

# --- now-unused address list, superseded by "octoprint" ---
/ip/firewall/address-list/remove [find where list=iot-internet]

# --- point remaining ether1 references at the WAN interface list ---
/ip/firewall/filter/set [find where comment="Add Syn Flood IP to the list"] in-interface="" in-interface-list=WAN
/ip/firewall/filter/set [find where comment="Drop to syn flood list"] in-interface="" in-interface-list=WAN
/ip/firewall/filter/set [find where comment="Port Scanner Detect"] in-interface="" in-interface-list=WAN
/ip/firewall/filter/set [find where comment="Drop to port scan list"] in-interface="" in-interface-list=WAN
/ip/firewall/filter/set [find where comment="defconf: drop all from WAN"] in-interface="" in-interface-list=WAN
/ip/firewall/filter/set [find where comment="Syn flood detect - any forwarded port"] in-interface="" in-interface-list=WAN
/ip/firewall/filter/set [find where comment="Drop syn flooders - inbound"] in-interface="" in-interface-list=WAN
/ip/firewall/nat/set [find where action=masquerade] out-interface="" out-interface-list=WAN

:put "Cleanup complete. Verify with:"
:put "/ip/firewall/filter/print"
:put "/ip/firewall/nat/print"
:put "/ip/firewall/address-list/print"
