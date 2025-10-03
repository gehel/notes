#!/usr/bin/env sh

projects="FY2025-2026-q2-sre"

while inotifywait -e MODIFY -r .; do
  for project in ${projects}; do
    mkdir -p output/${project}
    tj3 -o output/${project} ${project}.tjp
  done
  rsync -rav output/* people2004.codfw.wmnet:~/public_html/planning
done
