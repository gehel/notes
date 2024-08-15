#!/usr/bin/env sh

project=$1

while inotifywait -e MODIFY ${project}.tjp; do
  tj3 -o output/${project} ${project}.tjp
  rsync -rav output/${project} people2003.codfw.wmnet:~/public_html/planning
done

