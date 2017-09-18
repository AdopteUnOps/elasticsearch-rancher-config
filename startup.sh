#!/usr/bin/env bash
set -e

RANCHER_BASEURL="rancher-metadata.rancher.internal/latest"


echo "Installing custom elasticsearch config"
mkdir -p /usr/share/elasticsearch/config
# elasticsearch.yml
curl -so /usr/share/elasticsearch/config/elasticsearch.yml ${RANCHER_BASEURL}/self/service/metadata/elasticsearch-config

echo "Adding rack awareness to elasticsearch config"

# rack aware handling
nb_hosts=`curl --silent http://${RANCHER_BASEURL}/hosts | wc -l`
echo "Parsing rack values from $nb_hosts hosts ..."
rack_values=()
hostname_values=()
for (( i=0; i < ${nb_hosts}; i++ ))
do
   rack_label=`curl --silent "http://${RANCHER_BASEURL}/hosts/$i/labels/rack"`
   if [ "${rack_label}" != "Not found" ]; then
      rack_values+=(rack_label)
   fi
   hostname_values+=(`curl --silent "http://${RANCHER_BASEURL}/hosts/$i/hostname"`)
done

#fallback to hostname if no rack labels
use_hostname_as_rack_value=false
if [ ${#rack_values[@]} -eq 0 ]; then
  echo "no host labels 'rack' defined, will use hostname instead"
  rack_values=$hostname_values
  use_hostname_as_rack_value=true
fi

UNIQUE_RACK_VALUES=`printf "%s\n" "${rack_values[@]}" | sort -u | tr '\n' ',' | head -c-1`
echo "Following rack values found on all hosts: $UNIQUE_RACK_VALUES"

echo "Detecting current rack"
if [ ${use_hostname_as_rack_value} ]; then
  rack=`curl --silent http://${RANCHER_BASEURL}/self/host/hostname`
else
  rack=`curl --silent http://${RANCHER_BASEURL}/self/host/labels/rack`
fi
echo 'Current rack : ' $rack

echo "
cluster.routing.allocation.awareness.force.rack.values: \"${UNIQUE_RACK_VALUES}\"
cluster.routing.allocation.awareness.attributes: rack
node.attr.rack: \"${rack}\"
" >> /usr/share/elasticsearch/config/elasticsearch.yml

# role mapping specific
echo "installing custom role mapping"
mkdir -p /usr/share/elasticsearch/config/x-pack
curl -so /usr/share/elasticsearch/config/x-pack/role_mapping.yml ${RANCHER_BASEURL}/self/service/metadata/elasticsearch-role-config

# run elasticsearch
/usr/share/elasticsearch/bin/es-docker
