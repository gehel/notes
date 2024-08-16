#!/usr/bin/env sh

project=$1

mkdir -p output/${project}

while inotifywait -e MODIFY ${project}.tjp; do
  tj3 -o output/${project} ${project}.tjp
  rsync -rav output/${project} people2003.codfw.wmnet:~/public_html/planning
done

