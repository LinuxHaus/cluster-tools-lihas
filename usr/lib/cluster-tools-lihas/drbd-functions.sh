#!/bin/bash

drbdversion() {
  echo $(awk '$1 ~ /^version/ {gsub("[a-z].*","",$2); split($2, a, "."); printf("1%03i%03i%03i",a[1],a[2],a[3])}' /proc/drbd)
}

drbdprimaryforce() {
    drbdres=$1
    if [ $DRBDVERSION -ge 1008004000 ]; then
        drbdadm primary --force $drbdres
    else
        drbdadm -- -o primary $drbdres
    fi
}
