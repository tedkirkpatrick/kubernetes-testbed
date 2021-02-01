#!/usr/bin/env bash
# Set the Gatling user count and script name
# See Usage message for parameter details
# Prints updated YAML file to stdout, typically to pipe into kubectl.
# Example:
#      tools/set-gatling-params.sh 5 ReadMusicSim | kubectl ... apply -f - ...
#
# This script requires yq v4 or later.  This query language is unsupported by
# yq v1--v3.
#
# This script is unavoidably ugly because it requires sophisticated query facilities
# of yq v4 and then has to interpolate two shell variables into those queries.
#
# The basic logic:
# 1. We need two yq invocations, the first to set USERS, the second to set SCRIPT_NAME.
#    The output of the first is piped as input to the second.
# 2. The YAML input has two documents, the first defining the ServiceAccount, which
#    must pass unchanged, the second defining the Job, which must be updated.
#    The (select(di == 0)) clause selects the first document and passes it
#    unchanged, while the (select(di == 1) | ...) clause selects the second
#    document and passes it for further processing. The comma takes the union of
#    their results.
# 3. The clauses following the "select" for the second document identify a specific field
#    in the Job's container template and assign to that field via the '='
#    assignment operator.
#  
set -o nounset
set -o errexit

if [[ $# -ne 2 ]]
then
  echo "Usage: ${0} USER_COUNT SCRIPT_NAME"
  echo "  The script must be defined in package 'proj756'. Do not include the package prefix in script name."
  exit 1
fi

yq eval '(select(di == 0)) , (select(di == 1) | (.spec.template.spec.containers[0].env.[] | select(.name == "USERS") | .value) = "'${1}'")' cluster/gatling.yaml | \
  yq eval '(select(di == 0)) , (select(di == 1) | (.spec.template.spec.containers[0].args.[1]) = "proj756.'${2}'")' -
