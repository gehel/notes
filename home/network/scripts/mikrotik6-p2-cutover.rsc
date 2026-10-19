# mikrotik6 Phase 2 -- installs the "cutover" and "rollback" scripts in
# /system/script. rb5009-migration.md Phase 2 and Phase 3.
#
# This file only stores the two scripts. It does not run them.
# cutover:  removes the staging routes, enables the production addresses
#           (IPv4 and the three IPv6 from-pool ones), the three ND entries,
#           wireguard1, the three DHCP servers, the CAPsMAN manager, and
#           PoE on ether3 (mikrotik4).
# rollback: the exact reverse. .10.6 and the WAN are never touched.
# Both are safe to run twice (README: schedulers can fire twice). The DHCP
# [find] is safe: mikrotik6 has only the three production servers.
#
# The DHCPv6-PD client is not touched: it runs from Phase 2b on, and mikrotik6
# has its own delegation (2a02:1210:7621:9ac0::/58, 2026-10-19).
#
# Run AFTER the system, dhcp, firewall, capsman and both p2b-ipv6 scripts.
# Idempotent: an existing script gets its source replaced.
# Run with: /import mikrotik6-p2-cutover.rsc
#
# The whole body is one { } block, so that :local values persist across lines.

{
:local cutover ""
:set cutover ($cutover . ":log warning \"cutover: start\"\n")
:set cutover ($cutover . "/ip/route/remove [find where comment=staging]\n")
:set cutover ($cutover . "/ip/address/enable [find where comment=\"production, enabled by cutover\"]\n")
:set cutover ($cutover . "/ipv6/address/enable [find where comment=\"production, enabled by cutover\"]\n")
:set cutover ($cutover . "/ipv6/nd/enable [find]\n")
:set cutover ($cutover . "/interface/wireguard/enable [find where name=wireguard1]\n")
:set cutover ($cutover . "/ip/dhcp-server/enable [find]\n")
:set cutover ($cutover . "/caps-man/manager/set enabled=yes\n")
:set cutover ($cutover . "/interface/ethernet/poe/set [find where name=ether3] poe-out=auto-on\n")
:set cutover ($cutover . ":log warning \"cutover: done\"\n")

:local rollback ""
:set rollback ($rollback . ":log warning \"rollback: start\"\n")
:set rollback ($rollback . "/interface/ethernet/poe/set [find where name=ether3] poe-out=off\n")
:set rollback ($rollback . "/caps-man/manager/set enabled=no\n")
:set rollback ($rollback . "/ip/dhcp-server/disable [find]\n")
:set rollback ($rollback . "/interface/wireguard/disable [find where name=wireguard1]\n")
:set rollback ($rollback . "/ipv6/nd/disable [find]\n")
:set rollback ($rollback . "/ipv6/address/disable [find where comment=\"production, enabled by cutover\"]\n")
:set rollback ($rollback . "/ip/address/disable [find where comment=\"production, enabled by cutover\"]\n")
:set rollback ($rollback . "/ip/route/remove [find where comment=staging]\n")
:set rollback ($rollback . "/ip/route/add dst-address=192.168.20.0/24 gateway=192.168.10.1 comment=staging\n")
:set rollback ($rollback . "/ip/route/add dst-address=192.168.30.0/24 gateway=192.168.10.1 comment=staging\n")
:set rollback ($rollback . "/ip/route/add dst-address=192.168.50.0/24 gateway=192.168.10.1 comment=staging\n")
:set rollback ($rollback . ":log warning \"rollback: done\"\n")

:foreach n,src in={"cutover"=$cutover;"rollback"=$rollback} do={
    :local id [/system/script/find where name=$n]
    :if ([:len $id] = 0) do={
        /system/script/add name=$n policy=read,write,test source=$src
    } else={
        /system/script/set $id source=$src
    }
}

:put "mikrotik6-p2-cutover: cutover and rollback stored, NOT run"
:log info "mikrotik6-p2-cutover: done"
}
