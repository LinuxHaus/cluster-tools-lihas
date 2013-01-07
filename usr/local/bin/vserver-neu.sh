#!/bin/bash

[ -e /etc/cluster-tools-lihas.conf ] && . /etc/cluster-tools-lihas.conf

if [ ga$4 == ga ]; then
  echo "usage: $0 VSNAME IP SIZE CONTEXT [DRBDNUM]" >&2
  echo "usage: $0 test01 10.0.0.115 10G 115" >&2
  echo "usage: $0 test01 10.0.0.115 10G 115 3" >&2
  exit 1
fi

VSNAME=$1
IP=$2
SIZE=$3
CONTEXT=$4


# IF Abfragen nach dem installierten Software, die benoetigt wird
if !([ -e /usr/bin/which ]) ; then
        echo "which ist nicht installiert!!!"
	exit 1
fi

if !([ -e $(which parted) ]) ; then
	echo "Please Install parted"
	exit 1
fi

if !([ -e $(which crm) ]) ; then
	echo "Please Install crm"
	exit 1
fi

if !([ -e $(which drbdadm) ]) ; then
	echo "Please Install drbd"
	exit 1
fi

if !([ -e $(which awk) ]) ; then
	echo "Please Install awk"
	exit 1
fi

if !([ -e $(which sort) ]) ; then
	echo "Please Install sort"
	exit 1
fi

if !([ -e $(which tail) ]) ; then
	echo "Please Install tail"
	exit 1
fi

if !([ -e $(which printf) ]) ; then
	echo "Please Install printf"
	exit 1
fi


if !([ -e $(which ssh) ]) ; then
	echo "Please Install openssh"
	exit 1
fi

if !([ -e $(which lvcreate) ]) ; then
	echo "Please Install lvm2"
	exit 1
fi

if !([ -e $(which rsync) ]) ; then
	echo "Please Install rsync"
	exit 1
fi

if !([ -e $(which mktemp) ]) ; then
	echo "Please Install mktemp"
	exit 1
fi

if !([ -e $(which virsh) ]) ; then
	echo "Please Install libvirt-bin"
	exit 1
fi

BROADCAST=$(ipcalc $IP/$IF_LAN_NM | awk '$1 ~ /^Netmask:$/ {print $2})

if [ ga$5 == ga ]; then
  # Naechstes freies DRBD
  DRBD=$(($(awk '$1 ~ /^device$/ && $2 ~ /^\/dev\/drbd/ {gsub(";","",$2); gsub("/dev/drbd","",$2); print $2}' /etc/drbd.d/*.res | sort -un| tail -1)+1))
else
  DRBD=$5
fi

DRBDPORT=$(printf "%02i" $DRBD)

DUMMY=10

lvcreate -L$SIZE -n vs_$VSNAME $VG1
ssh $HOST2 lvcreate -L$SIZE -n vs_$VSNAME $VG2

cat <<-EOF > /etc/drbd.d/vs_$VSNAME.res
resource vs_$VSNAME {  
        protocol        C;
        syncer {
                rate    2000M;
        }
        on $HOST1 {
                device          /dev/drbd$DRBD;
                disk            /dev/$VG1/vs_$VSNAME;
                flexible-meta-disk      internal;
                address         $IP_DRBD1:77$DRBDPORT;
        }
        on $HOST2 {
                device          /dev/drbd$DRBD;
                disk            /dev/$VG2/vs_$VSNAME;
                flexible-meta-disk      internal;
                address         $IP_DRBD2:77$DRBDPORT;
        }
}
EOF

rsync -rlHpogDtSvx /etc/drbd.d $HOST2:/etc/
yes yes | drbdadm create-md vs_$VSNAME
drbdadm up vs_$VSNAME
ssh $HOST2 "(yes yes | drbdadm create-md vs_$VSNAME && drbdadm up vs_$VSNAME)"

drbdadm -- -o primary vs_$VSNAME

mkfs.ext4 -L vs_$VSNAME /dev/drbd$DRBD
mount /dev/drbd$DRBD /mnt
vserver $VSNAME build --context $CONTEXT --interface $IF_LAN:$IP/$IF_LAN_NM --hostname $VSNAME -m debootstrap -- -d $DEBIANDIST
cat $VSERVER_TEMPLATE/etc/apt/sources.list > $VSERVER_BASE/$VSNAME/etc/apt/sources.list
sed -i '/tmpfs/d' /etc/vservers/$VSNAME/fstab
touch /etc/vservers/$VSNAME/interfaces/0/nodev
mv $VSERVER_BASE/$VSNAME/* /mnt/
umount /mnt 

ssh $HOST2 mkdir $VSERVER_BASE/$VSNAME

rsync -rlHpogDtSvx /etc/vservers $HOST2:/etc/

cat <<-EOF | cibadmin -M -p
  <configuration>
    <resources>
      <master id="ms_$VSNAME">
        <meta_attributes id="ms_$VSNAME-meta_attributes">
          <nvpair id="ms_$VSNAME-meta_attributes-clone-max" name="clone-max" value="2"/>
          <nvpair id="ms_$VSNAME-meta_attributes-notify" name="notify" value="true"/>
        </meta_attributes>
        <primitive id="res_drbd_drbd$DRBD_$VSNAME" class="ocf" provider="linbit" type="drbd">
          <instance_attributes id="res_drbd_drbd$DRBD_$VSNAME-instance_attributes">
            <nvpair id="nvpair-res_drbd_drbd$DRBD_$VSNAME-drbd_resource" name="drbd_resource" value="vs_$VSNAME"/>
          </instance_attributes>
          <operations id="res_drbd_drbd$DRBD_$VSNAME-operations">
            <op interval="0" id="op-res_drbd_drbd$DRBD_$VSNAME-start" name="start" timeout="240"/>
            <op interval="0" id="op-res_drbd_drbd$DRBD_$VSNAME-promote" name="promote" timeout="90"/>
            <op interval="0" id="op-res_drbd_drbd$DRBD_$VSNAME-demote" name="demote" timeout="90"/>
            <op interval="0" id="op-res_drbd_drbd$DRBD_$VSNAME-stop" name="stop" timeout="100"/>
            <op id="op-res_drbd_drbd$DRBD_$VSNAME-monitor" name="monitor" interval="10" timeout="20" start-delay="1min"/>
            <op interval="0" id="op-res_drbd_drbd$DRBD_$VSNAME-notify" name="notify" timeout="90"/>
          </operations>
          <meta_attributes id="res_drbd_drbd$DRBD_$VSNAME-meta_attributes">
            <nvpair id="res_drbd_drbd$DRBD_$VSNAME-meta_attributes-is-managed" name="is-managed" value="true"/>
          </meta_attributes>
        </primitive>
      </master>
      <group id="grp_$VSNAME">
        <meta_attributes id="grp_$VSNAME-meta_attributes"/>
        <primitive id="res_fs_$VSNAME" class="ocf" provider="heartbeat" type="Filesystem">
          <instance_attributes id="res_fs_$VSNAME-instance_attributes">
            <nvpair id="nvpair-res_fs_$VSNAME-device" name="device" value="/dev/drbd$DRBD"/>
            <nvpair id="nvpair-res_fs_$VSNAME-directory" name="directory" value="$VSERVER_BASE/$VSNAME"/>
            <nvpair id="nvpair-res_fs_$VSNAME-fstype" name="fstype" value="ext4"/>
            <nvpair id="nvpair-res_fs_$VSNAME-options" name="options" value="noatime,stripe=64,barrier=0"/>
          </instance_attributes>
          <operations id="res_fs_$VSNAME-operations">
            <op interval="0" id="op-res_fs_$VSNAME-start" name="start" timeout="600"/>
            <op interval="0" id="op-res_fs_$VSNAME-stop" name="stop" timeout="60"/>
            <op id="op-res_fs_$VSNAME-monitor" name="monitor" interval="20" timeout="40" start-delay="0"/>
            <op interval="0" id="op-res_fs_$VSNAME-notify" name="notify" timeout="60"/>
          </operations>
          <meta_attributes id="res_fs_$VSNAME-meta_attributes">
            <nvpair id="res_fs_$VSNAME-meta_attributes-is-managed" name="is-managed" value="true"/>
            <nvpair id="res_fs_$VSNAME-meta_attributes-target-role" name="target-role" value="started"/>
          </meta_attributes>
        </primitive>
        <primitive id="res_IPaddr2_ip_$VSNAME" class="ocf" provider="heartbeat" type="IPaddr2">
          <instance_attributes id="res_IPaddr2_ip_$VSNAME-instance_attributes">
            <nvpair id="nvpair-res_IPaddr2_ip_$VSNAME-ip" name="ip" value="$IP"/>
            <nvpair id="nvpair-res_IPaddr2_ip_$VSNAME-nic" name="nic" value="$IF_LAN"/>
            <nvpair id="nvpair-res_IPaddr2_ip_$VSNAME-cidr_netmask" name="cidr_netmask" value="$IF_LAN_NM"/>
            <nvpair id="nvpair-res_IPaddr2_ip_$VSNAME-broadcast" name="broadcast" value="$BROADCAST"/>
          </instance_attributes>
          <operations id="res_IPaddr2_ip_$VSNAME-operations">
            <op interval="0" id="op-res_IPaddr2_ip_$VSNAME-start" name="start" timeout="20"/>
            <op interval="0" id="op-res_IPaddr2_ip_$VSNAME-stop" name="stop" timeout="20"/>
            <op id="op-res_IPaddr2_ip_$VSNAME-monitor" name="monitor" interval="10" timeout="20" start-delay="0"/>
          </operations>
          <meta_attributes id="res_IPaddr2_ip_$VSNAME-meta_attributes">
            <nvpair id="res_IPaddr2_ip_$VSNAME-meta_attributes-target-role" name="target-role" value="started"/>
          </meta_attributes>
        </primitive>
        <primitive id="res_VServer-lihas_vs_$VSNAME" class="ocf" provider="lihas" type="VServer-lihas">
          <instance_attributes id="res_VServer-lihas_vs_$VSNAME-instance_attributes">
            <nvpair id="nvpair-res_VServer-lihas_vs_$VSNAME-vservername" name="vservername" value="$VSNAME"/>
          </instance_attributes>
          <operations id="res_VServer-lihas_vs_$VSNAME-operations">
            <op interval="0" id="op-res_VServer-lihas_vs_$VSNAME-start" name="start" timeout="600"/>
            <op interval="0" id="op-res_VServer-lihas_vs_$VSNAME-stop" name="stop" timeout="180"/>
            <op id="op-res_VServer-lihas_vs_$VSNAME-monitor" name="monitor" interval="10" timeout="20" start-delay="5"/>
          </operations>
          <meta_attributes id="res_VServer-lihas_vs_$VSNAME-meta_attributes">
            <nvpair id="res_VServer-lihas_vs_$VSNAME-meta_attributes-is-managed" name="is-managed" value="true"/>
            <nvpair id="res_VServer-lihas_vs_$VSNAME-meta_attributes-target-role" name="target-role" value="started"/>
          </meta_attributes>
        </primitive>
      </group>
    </resources>
    <constraints>
      <rsc_location id="loc_ms_$VSNAME-$HOST1" rsc="ms_$VSNAME" node="$HOST1" score="2"/>
      <rsc_location id="loc_ms_$VSNAME-$HOST2" rsc="ms_$VSNAME" node="$HOST2" score="0"/>
      <rsc_colocation id="col_grp_$VSNAME-ms_$VSNAME" score="INFINITY" with-rsc-role="Master" rsc="grp_$VSNAME" with-rsc="ms_$VSNAME"/>
      <rsc_order id="ord_ms_$VSNAME-grp_$VSNAME" score="INFINITY" first-action="promote" then-action="start" first="ms_$VSNAME" then="grp_$VSNAME"/>
    </constraints>
  </configuration>
EOF
