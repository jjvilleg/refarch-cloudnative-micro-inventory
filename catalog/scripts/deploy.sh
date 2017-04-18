#!/bin/bash

function get_elastic_secret {
	echo $(kubectl --token=${token} get secrets | grep "compose-for-elasticsearch" | awk '{print $1}')
}

set -x

token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
cluster_name=$(cat /var/run/secrets/bx-auth-secret/CLUSTER_NAME)
build_number=$1

# Check if elasticsearch secret exists
elastic_secret=$(get_elastic_secret)

if [[ -z "${elastic_secret// }" ]]; then
	echo "elasticsearch secret does not exist. Creating"
	elastic_service="\"$(bx service list | grep "compose-for-elasticsearch" | head -1 | sed -e 's/compose-for-elasticsearch.*//' | sed 's/[[:blank:]]*$//')\""

	if [[ -z "${elastic_secret// }" ]]; then
		echo "Cannot create secret. No service instance exists for compose-for-elasticsearch."
		exit 1
	fi

	echo "Creating secret from ${elastic_service}"
	bx cs cluster-service-bind $cluster_name default $elastic_service

	if [ $? -ne 0 ]; then
	  echo "Could not create secret for ${elastic_service} service."
	  exit 1
	fi

	elastic_secret=$(get_elastic_secret)

	if [[ -z "${elastic_secret// }" ]]; then
		echo "Cannot retrieve secret for ${elastic_service} service."
		exit 1
	fi
fi

cd ../kube

# Enter secret and image name into yaml
sed -i.bak s%binding-compose-for-elasticsearch%${elastic_secret}%g service.yml
sed -i.bak s%registry.ng.bluemix.net/chrisking/catalog:v1%registry.ng.bluemix.net/chrisking/catalog:${build_number}%g service.yml

# Delete previous service
# Do rolling update here
echo -e "Deleting previous version of catalog if it exists"
kubectl --token=${token} delete --ignore-not-found=true -f service.yml

# Deploy service
echo -e "Creating pods"
kubectl --token=${token} create -f service.yml

IP_ADDR=$(kubectl --token=${token} get service catalog | grep catalog | awk '{print $3}')
PORT=$(kubectl --token=${token} get services catalog | grep catalog | awk '{print $4}' | sed 's/:.*//')

echo "View the catalog at http://$IP_ADDR:$PORT/micro/items"

cd ../scripts
set +x