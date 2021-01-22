#!/usr/bin/env bash
# Wait for a condition to become true on a single pod in namespace $1
set -o nounset
set -o errexit
if [[ $# -ne 6 ]]
then
  echo "Must pass six parameters"
  exit 1
fi
while [ "$(kubectl get -n ${1} pods -l ${2} -o jsonpath=${3})" = "${4}" ]
do
    echo "${5} not yet ${6}. Sleeping 1 s"
    sleep 1
done
echo "${5} is ${6}"
