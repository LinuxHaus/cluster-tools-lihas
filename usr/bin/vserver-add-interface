#!/bin/bash
LC_ALL=C


VSNAME=$1
INTERFACE=$2
IP=$3
NETMASK=$4


[ -e /etc/cluster-tools-lihas.conf ] && . /etc/cluster-tools-lihas.conf

if [ ga$3 == ga ]; then
  echo "Only on active side"
  echo "usage: $0 VSNAME INTERFACE IP NETMASK" >&2
  echo "usage: $0 test01 br0 10.0.0.5 24" >&2
  exit 1
fi

# IF Abfragen nach dem installierten Software, die benoetigt wird
if !([ -e /usr/bin/which ]) ; then echo "which ist nicht installiert!!!"; exit 1; fi
if !([ -e $(which crm) ]) ; then echo "Please Install crm"; exit 1; fi
if !([ -e $(which awk) ]) ; then echo "Please Install awk"; exit 1; fi
if !([ -e $(which sort) ]) ; then echo "Please Install sort"; exit 1; fi
if !([ -e $(which tail) ]) ; then echo "Please Install tail"; exit 1; fi
if !([ -e $(which printf) ]) ; then echo "Please Install printf"; exit 1; fi
if !([ -e $(which ssh) ]) ; then echo "Please Install openssh"; exit 1; fi
if !([ -e $(which rsync) ]) ; then echo "Please Install rsync"; exit 1; fi
if !([ -e $(which ip) ]) ; then echo "Please Install iproute"; exit 1; fi
if !([ -e $(which naddress) ]) ; then echo "Please Install util-vserver-core"; exit 1; fi


check_vserver ()
{
	find -type d -name "$VSNAME"
	if [ $? -ne 0 ]; then
		echo "$VSNAME not exist"
		exit 1
	fi
}


check_ip ()
{


	#check lokal system
	FOUND=`ip a l | grep -w $IP | awk '{print $2}' |awk -F "/" '{print $1}'`
	if [ ! -z $FOUND ]; then
		if [ $IP = $FOUND ]; then
			echo "IP $IP seems to be used on $HOST1"
			exit 1
		fi
	fi

	#check otherside
	FOUND=`ssh $HOST2 ip a l | grep -w $IP | awk '{print $2}' |awk -F "/" '{print $1}'`
	if [ ! -z $FOUND ]; then
		if [ $IP = $FOUND ]; then
			echo "IP $IP seems to be used on $HOST2"
			exit 1
		fi
	fi
	
	#check inactive vserver
	FOUND=`egrep -R -w $IP /etc/vservers/*/interfaces/`
	if [ $? -eq 0 ]; then
		TMP=`echo $FOUND | awk -F "/" '{print $4}'`
		echo "$IP is used in VServer $TMP "
		exit 1
	fi

	#check network
	FOUND=`ping -c2 $IP`
	if [ $? -eq 0 ]; then
		echo "IP $IP seems to be used on network"
		exit 1
	fi
}


add_ip ()
{
	ip a add $IP/$NETMASK dev $INTERFACE
	if [ $? -gt 0 ]; then
		echo "Can't add $IP to $INTERFACE"
		exit 1
	fi
	NUMBER=`ls /etc/vservers/$VSNAME/interfaces/ | sort -n | tail -1`
	NUMBER=$(( $NUMBER + 1 ))
	mkdir /etc/vservers/$VSNAME/interfaces/$NUMBER
	echo $IP > /etc/vservers/$VSNAME/interfaces/$NUMBER/ip
	echo $NETMASK > /etc/vservers/$VSNAME/interfaces/$NUMBER/prefix
	echo $INTERFACE > /etc/vservers/$VSNAME/interfaces/$NUMBER/dev
	touch /etc/vservers/$VSNAME/interfaces/$NUMBER/nodev

	rsync -rlHpogDtSvx /etc/vservers/$VSNAME $HOST2:/etc/vservers/
		

	naddress --nid $VSNAME --add  --ip $IP --bcast $NETMASK
	if [ $? -ne 0 ]; then
		echo "Can't add $IP to $VSNAME"
		exit 1
	fi

}


add_crm ()
{
RESNAME=$VSNAME\_$IP


crm resource unmanage grp_$VSNAME

cat <<EOF | crm configure
primitive res_IPaddr2_ip_$RESNAME ocf:heartbeat:IPaddr2 \
        params ip="$IP" nic="$INTERFACE" cidr_netmask="$NETMASK" broadcast="" \
        operations \$id="res_IPaddr2_ip_$RESNAME-operations" \
        op start interval="0" timeout="20" \
        op stop interval="0" timeout="20" \
        op monitor interval="10" timeout="20" start-delay="0" \
	meta target-role="started" \
	meta is-managed="false"
commit
EOF

EDITOR="sed -i '/^group grp_'$VSNAME' /,/[^\\]/{s/ res_VServer/ res_IPaddr2_ip_'$RESNAME' res_VServer/}'" crm configure edit


crm resource cleanup res_IPaddr2_ip_$RESNAME
crm resource start res_IPaddr2_ip_$RESNAME
crm resource cleanup res_IPaddr2_ip_$RESNAME
crm resource cleanup res_VServer-lihas_vs_$VSNAME

crm resource manage grp_$VSNAME
}


check_vserver
check_ip
add_ip
add_crm
