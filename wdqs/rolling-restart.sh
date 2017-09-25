#!/usr/bin/env bash

hosts="
wdqs1001.eqiad.wmnet
wdqs1002.eqiad.wmnet
wdqs1003.eqiad.wmnet
wdqs2001.codfw.wmnet
wdqs2002.codfw.wmnet
wdqs2003.codfw.wmnet
"

icinga=einsteinium.wikimedia.org

ssh ${icinga} sudo icinga-downtime -h ${hostname} -d 1200 -r "restart in progress"


for host in ${hosts} ; do
    ssh ${host} id
done
