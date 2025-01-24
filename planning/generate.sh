#!/usr/bin/env sh

projects="q3-dpe q3-search q3-sre"

mkdir -p output/${project}

while inotifywait -e MODIFY -r .; do
  for project in ${projects}; do
    mkdir -p output/${project}
    tj3 -o output/${project} ${project}.tjp
  done
  rsync -rav output/* people2003.codfw.wmnet:~/public_html/planning
done
