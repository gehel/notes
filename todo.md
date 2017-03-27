# My Personal todo list

## Urgent
* Debian package osmborder (https://phabricator.wikimedia.org/T157610)
* upgrade to elasticsearch 5

## Long term improvements

* Make OSM master switchable without reimports
  (https://phabricator.wikimedia.org/T137378)
* get rid of HTTP for elasticsearch (use only HTTPS)
* investigate and tune I/O bottleneck on elasticsearch
  (https://phabricator.wikimedia.org/T153083)
* improve cluster restart orchestration
  (https://phabricator.wikimedia.org/T145065)
  * have a way to pause / resume / flush all writes (investigate all write
    sources)
  * use cumin as orchestration library
* cleanup our postgresql puppet module
* tune heap size (and maybe GC) on elasticsearch
  (https://phabricator.wikimedia.org/T156137)
* dedicated master nodes for elasticsearch
  (https://phabricator.wikimedia.org/T130590)
* make elasticsearch more resilient to small network hiccups
  (https://phabricator.wikimedia.org/T154765)
  * this needs some non trivial amount of testing, probably by creating a
    dedicated cluster on labs and having some load test / validation scripts
* cleanup wdqs build process
* investigate data discrepancies between wdqs nodes
* improve (speed) data import on wdqs
