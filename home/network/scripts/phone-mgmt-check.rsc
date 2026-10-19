# phone-mgmt-check.rsc -- make sure the phone (192.168.50.2, via wireguard1
# on mikrotik1) can log in to this device's management.
#
# Three independent gates (see README hard-won lessons):
#   1. 192.168.50.2 in the mgmt address-list (input-chain accept).
#   2. 192.168.50.0/24 in the admin user's own address= restriction.
#   3. A route back to 192.168.50.0/24. An L2 switch with only a
#      connected route accepts the SYN and never answers, silently.
#
# Idempotent. Safe on every device; meant for mikrotik4 and mikrotik5,
# the two devices built after the 2026-09-28 phone-mgmt rollout and never
# tested from the phone. Run with: /import phone-mgmt-check.rsc

# --- 1. mgmt address-list ---------------------------------------------------
# Single-condition find, narrow in script logic (README: "and" in find is
# unreliable).
:local found false
:foreach i in=[/ip/firewall/address-list/find where address=192.168.50.2] do={
    :if ([/ip/firewall/address-list/get $i list] = "mgmt") do={ :set found true }
}
:if ($found) do={
    :put "1. mgmt: phone already present"
} else={
    /ip/firewall/address-list/add list=mgmt address=192.168.50.2 comment="phone (MrG Galaxy S24), via wireguard1"
    :put "1. mgmt: phone ADDED"
}

# --- 2. admin address restriction --------------------------------------------
# /get can return an array (README lesson), so compare element by element.
:local addrs [/user/get [find name=admin] address]
:local hasTunnel false
:foreach a in=$addrs do={
    :if ([:tostr $a] = "192.168.50.0/24") do={ :set hasTunnel true }
}
:if ($hasTunnel) do={
    :put "2. admin address: tunnel subnet already present"
} else={
    :if ([:tostr $addrs] = "192.168.10.0/24") do={
        /user/set [find name=admin] address=192.168.10.0/24,192.168.50.0/24
        :put "2. admin address: WIDENED to 192.168.10.0/24,192.168.50.0/24"
    } else={
        :put ("2. admin address: UNEXPECTED value '" . [:tostr $addrs] . "' -- not touched, fix by hand")
    }
}

# --- 3. return route ---------------------------------------------------------
:local routed false
:foreach r in=[/ip/route/find where dst-address=0.0.0.0/0] do={
    :if ([/ip/route/get $r active]) do={ :set routed true }
}
:foreach r in=[/ip/route/find where dst-address=192.168.50.0/24] do={
    :if ([/ip/route/get $r active]) do={ :set routed true }
}
:if ($routed) do={
    :put "3. route: default or tunnel route already active"
} else={
    /ip/route/add dst-address=0.0.0.0/0 gateway=192.168.10.1 comment="static default"
    :put "3. route: default via 192.168.10.1 ADDED"
}

# --- Verify (always re-print; README: a set on an empty find is silent) ------
/ip/firewall/address-list/print where list=mgmt
/user/print detail where name=admin
/ip/route/print
