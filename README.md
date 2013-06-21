cluster-tools-lihas
===================

vserver-neu.sh: create a new linux vserver (http://linux-vserver.org/) in your cluster
kvm-neu.sh: create a new empty KVM within your cluster
vserver-add-disk.sh: add a new drbd-volume insider your vserver and move the original data there

debian packages available at
  deb http://ftp.lihas.de/debian stable main
Needs heartbeat2-scripts-lihas from http://ftp.lihas.de/debian/stable/main.
  apt-get install cluster-tools-lihas heartbeat2-scripts-lihas
