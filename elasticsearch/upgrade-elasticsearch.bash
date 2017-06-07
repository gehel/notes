#!/usr/bin/env bash
set -e

es_server_prefix=elastic10
es_server_suffix=.eqiad.wmnet
first_server_index=20
nb_of_servers_in_cluster=36

icinga=tegmen.wikimedia.org
curator="curator --config /etc/curator/config.yaml"

for i in $(seq -w ${first_server_index} ${nb_of_servers_in_cluster}); do
    hostname="${es_server_prefix}${i}"
    server="${es_server_prefix}${i}${es_server_suffix}"

    echo "make sure cluster is green before we start"
    ssh ${server} "until curl -s 127.0.0.1:9200/_cat/health | grep green; do echo -n .; sleep 10; done"

    echo "ready to start restart ${server}, press [enter] to start"
    read

    echo "disabling replication"
    ssh ${server} sudo ${curator} /etc/curator/disable-shard-allocation.yaml

    echo "flushing markers"
    ssh ${server} curl -s -XPOST '127.0.0.1:9200/_flush/synced?pretty'

    echo "disabling icinga alerts for ${hostname}"
    ssh ${icinga} sudo icinga-downtime -h ${hostname} -d 600 -r "upgrade in progress"

    echo "disable puppet on ${server}"
    ssh ${server} sudo puppet agent --disable "upgrade in progress"

    echo "stop elasticsearch"
    ssh ${server} sudo service elasticsearch stop

    echo "upgrade elasticsearch"
    ssh ${server} sudo apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install elasticsearch

    echo "rebooting server"
    ssh ${server} "sudo nohup reboot &> /dev/null & exit"

    sleep 30

    echo "waiting for server to be up"
    until ssh ${server} true &> /dev/null; do
        echo -n .
        sleep 1
    done
    echo "server is up"

    echo "waiting for elasticsearch to be started"
    until ssh ${server} curl -s 127.0.0.1:9200/_cat/health; do
        echo -n '.'
        sleep 1
    done
    echo "elasticsearch is started"

    echo "enabling replication"
    ssh ${server} sudo ${curator} /etc/curator/enable-shard-allocation.yaml

    echo "re-enabling puppet on ${server}"
    ssh ${server} sudo puppet agent --enable


    echo "waiting for cluster recovery"
    ssh ${server} "until curl -s 127.0.0.1:9200/_cat/health | grep green; do echo -n .; sleep 10; done"

    echo "waiting for all relocation to stabilize"
    ssh ${server} "while curl -s 127.0.0.1:9200/_cat/recovery | grep -v done; do echo -n .; sleep 10; done"

    echo "Done for ${server}"
    echo "=============================================="
done