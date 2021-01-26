#!/usr/bin/env bash
# Simple tool to ensure that templates are regenerated before a make
# ${1}: Makefile to run. Any version can be specified. Examples
#          k8s-tpl, k8s, k8s-tpl.mak, k8s.mak
#       will all be transformed to k8s.mak
# ${2}: Target in makefil
# All others: Passed to make
set -o nounset
file=${1/.mak/}    # Strip any extension
file=${file/-tpl/} # Strip any template suffix
target=${2}
# Remaining args become $@
shift 2
make -f k8s-tpl.mak templates
make -f ${file}.mak -e ${target} "$@"
