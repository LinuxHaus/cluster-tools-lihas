#!/bin/bash

drbdversion() {
  echo $(awk '$1 ~ /^version/ {gsub("[a-z].*","",$2); split($2, a, "."); printf("1%03i%03i%03i",a[1],a[2],a[3])}' /proc/drbd)
}

drbdnextfree() {
  echo $(($(awk '$1 ~ /^device$/ && $2 ~ /^\/dev\/drbd/ {gsub(";","",$2); gsub("/dev/drbd","",$2); print $2}' /etc/drbd.d/*.res | sort -un| tail -1)+1))
}

drbdprimaryforce() {
    DRBDVERSION=$1
    drbdres=$2
    if [ $DRBDVERSION -ge 1008004000 ]; then
        drbdadm primary --force $drbdres
    else
        drbdadm -- -o primary $drbdres
    fi
}
