#!/usr/bin/fish

while inotifywait -e MODIFY wdqs-split-graph.tjp;
  tj3 -o output/wdqs-split-graph wdqs-split-graph.tjp
  rsync -rav output/wdqs-split-graph people2003.codfw.wmnet:~/public_html/planning
end
