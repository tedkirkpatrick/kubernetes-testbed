#!/usr/bin/env bash
# Build ConfigMap definition from one or more text files and print result on stdout
#
# The output is typically piped into `kubectl apply -f -`
#
# This script takes a header that defines and names the resource.
# The script appends the files to that header. The appended files
# hav four spaces prefixing every line so that they fits the
# YAML indentation requirements.
#
# $1: File specifying YAML header to precede the data
# $2, ...: Files to be incorporated into ConfigMap
#   In the resulting CM, each file's base name (the name minus any
#   leading directories) will be prefixed by two spaces,
#   then each line will be prefixed by 4 spaces so
#   that the YAML parser considers it part of the object
#   defined by the header.
#   All trailing spaces and newlines are preserved.
set -o nounset
set -o errexit

if [[ $# -lt 2 ]]
then
  echo "${0} must be passed at least two arguments"
  exit 1
fi

function add() {
  sed -e 's|^|    |' < ${1}
}

# Begin with header
cat $1

shift
for fn in $*
do
  echo "  $(/usr/bin/basename ${fn}): |"
  add ${fn}
done
