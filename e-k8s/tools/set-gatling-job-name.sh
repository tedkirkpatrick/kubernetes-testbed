#!/usr/bin/env bash
# Set the Gatling Job name---for 2nd, 3rd, ... Gatling runs
# Strips definition of ServiceAccount becuase that should already exist
# See Usage message for parameter details
# Usually takes input from set-gatling-params.sh and sends output to kubectl
# Example:
#      tools/set-gatling-params.sh 5 ReadMusicSim | tools/set-gatling-job-name.sh myjob | kubectl ... apply -f - ...
#
# This script requires yq v4 or later.  This query language is unsupported by
# yq v1--v3.
#
# See the comments in set-gatling-params.sh for help decoding the yq query.
#  
set -o nounset
set -o errexit

if [[ $# -ne 1 ]]
then
  echo "Usage: ${0} JOB_NAME"
  echo "  JOB_NAME must differ from any existing Job (including completed Jobs)"
  echo "  in the same Kubernetes Namespace.  Kubernetes requires object names "
  echo "  to be all lower case, so this script converts the name before "
  echo "  updating the YAML."
  exit 1
fi

# Convert to lower case
LC_JN=$(echo "${1}" | tr '[:upper:]' '[:lower:]')
yq eval '(select(di == 1) | .metadata.name = "'${LC_JN}'")' -
