#!/usr/bin/env bash

hosts="
 wdqs1003.eqiad.wmnet
 wdqs1004.eqiad.wmnet
 wdqs1005.eqiad.wmnet
 wdqs2001.codfw.wmnet
 wdqs2002.codfw.wmnet
 wdqs2003.codfw.wmnet
"
dnl_dir=~/wdqs-gc


mkdir -p ${dnl_dir}

for host in ${hosts}; do
  echo "downloading GC logs for ${host}"
  mkdir -p ${dnl_dir}/${host}
  files=$(ssh ${host} find "/var/log/wdqs/wdqs-blazegraph_jvm_gc*" -type f -mtime -3)
  for f in ${files}; do
    rsync -HPza ${host}:${f} ${dnl_dir}/${host}
  done
done

rsync -HPza ${dnl_dir} rutherfordium.eqiad.wmnet:~/public_html