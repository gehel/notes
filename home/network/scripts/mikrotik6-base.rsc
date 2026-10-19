# mikrotik6 (RB5009UPr+S+IN) -- base staging identity.
# One-shot: run via /system/reset-configuration no-defaults=yes
# run-after-reset=mikrotik6-base.rsc, then delete this file once verified
# (see README.md's scripts/ convention). rb5009-migration.md Phase 1.
#
# Result: VLAN-aware bridge-main, management at 192.168.10.6 on vlan-users,
# WAN DHCP client on ether1, input/forward firewall closed except for mgmt
# hosts, IPv6 off, PoE off on every port. No production service (DHCP
# server, routing for the VLANs, NAT, CAPsMAN, WireGuard) -- Phase 2.
#
# Assumes the RB5009's default port names: ether1-ether8, sfp-sfpplus1.
# Check /interface/print before the reset.

# run-after-reset starts before every interface exists.
:delay 15s

/system identity set name=mikrotik6
/system clock set time-zone-name=Europe/Zurich

# PoE off everywhere. ether3 (mikrotik4) goes to auto-on at cutover.
/interface ethernet poe set [find] poe-out=off

# Interface lists first: firewall and services below reference them.
/interface list add name=WAN comment="the WAN-facing interface(s)"
/interface list add name=discover
/interface list add name=mactel
/interface list add name=mac-winbox
/interface list member add list=WAN interface=ether1

# Bridge. vlan-filtering on from the start: nothing is connected yet.
/interface bridge add name=bridge-main vlan-filtering=yes comment="mikrotik6 LAN"
/interface bridge port add bridge=bridge-main interface=ether2 pvid=10 comment="trunk to mikrotik2"
/interface bridge port add bridge=bridge-main interface=ether3 pvid=10 comment="mikrotik4 (cAP XL ac)"
/interface bridge port add bridge=bridge-main interface=ether4 pvid=10
/interface bridge port add bridge=bridge-main interface=ether5 pvid=10
/interface bridge port add bridge=bridge-main interface=ether6 pvid=10
/interface bridge port add bridge=bridge-main interface=ether7 pvid=10
/interface bridge port add bridge=bridge-main interface=ether8 pvid=10
/interface bridge port add bridge=bridge-main interface=sfp-sfpplus1 pvid=10

/interface bridge vlan add bridge=bridge-main vlan-ids=10 tagged=bridge-main untagged=ether2,ether3,ether4,ether5,ether6,ether7,ether8,sfp-sfpplus1
/interface bridge vlan add bridge=bridge-main vlan-ids=20 tagged=bridge-main,ether2
/interface bridge vlan add bridge=bridge-main vlan-ids=30 tagged=bridge-main,ether2,ether3

/interface vlan add interface=bridge-main name=vlan-users vlan-id=10
/interface vlan add interface=bridge-main name=vlan-services vlan-id=20
/interface vlan add interface=bridge-main name=vlan-iot vlan-id=30

/interface list member add list=discover interface=bridge-main
/interface list member add list=mactel interface=bridge-main
/interface list member add list=mac-winbox interface=bridge-main

# Management address. Permanent: it stays after cutover.
/ip address add address=192.168.10.6/24 interface=vlan-users comment="mikrotik6 management"

# WAN. Default route and DNS come from the Internet-Box until cutover.
/ip dhcp-client add interface=ether1 use-peer-dns=yes add-default-route=yes comment="WAN, Internet-Box"

# Staging only: reach the other VLANs and the WireGuard subnet through
# mikrotik1, not through the WAN default route. Remove at cutover.
/ip route add dst-address=192.168.20.0/24 gateway=192.168.10.1 comment=staging
/ip route add dst-address=192.168.30.0/24 gateway=192.168.10.1 comment=staging
/ip route add dst-address=192.168.50.0/24 gateway=192.168.10.1 comment=staging

# mgmt list BEFORE the rule that uses it (README hard-won lesson).
/ip firewall address-list add list=mgmt address=192.168.10.1 comment=mikrotik1
/ip firewall address-list add list=mgmt address=192.168.10.2 comment=mikrotik2
/ip firewall address-list add list=mgmt address=192.168.10.3 comment=mikrotik3
/ip firewall address-list add list=mgmt address=192.168.10.4 comment=mikrotik4
/ip firewall address-list add list=mgmt address=192.168.10.5 comment=mikrotik5
/ip firewall address-list add list=mgmt address=192.168.10.90 comment=desktop
/ip firewall address-list add list=mgmt address=192.168.10.92 comment="gimli, work laptop"
/ip firewall address-list add list=mgmt address=192.168.50.2 comment="phone (MrG Galaxy S24), via wireguard1"

/ip firewall filter add chain=input action=accept connection-state=established,related comment="accept established,related"
/ip firewall filter add chain=input action=drop connection-state=invalid comment="drop invalid"
/ip firewall filter add chain=input action=drop in-interface-list=WAN comment="drop all from WAN"
/ip firewall filter add chain=input action=accept protocol=icmp comment="accept ICMP"
/ip firewall filter add chain=input action=accept src-address-list=mgmt comment="mgmt hosts to router"
/ip firewall filter add chain=input action=drop comment="drop anything else"
/ip firewall filter add chain=forward action=drop comment="staging: no forwarding until Phase 2"

# IPv6 off until Phase 2 ports its firewall. Takes effect after a reboot.
/ipv6 settings set disable-ipv6=yes

# Services: same baseline as the rest of the fleet.
/ip service set ftp disabled=yes
/ip service set telnet disabled=yes
/ip service set www-ssl disabled=yes
/ip service set api-ssl disabled=yes
/ip service set reverse-proxy disabled=yes
/ip ssh set strong-crypto=yes host-key-size=4096
/ip neighbor discovery-settings set discover-interface-list=discover
/tool mac-server set allowed-interface-list=mactel
/tool mac-server mac-winbox set allowed-interface-list=mac-winbox

# admin: same address restriction as mikrotik1, and the desktop's SSH key
# (uploaded before the reset, files survive it).
/user set [find name=admin] address=192.168.10.0/24,192.168.50.0/24
:do { /user ssh-keys import user=admin public-key-file=id_rsa.pub } on-error={ :log warning "mikrotik6-base: ssh key import failed" }

:log info "mikrotik6-base: done"
