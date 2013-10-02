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
if [ ! -e /usr/bin/which    ] ; then echo "which ist nicht installiert!!!"; exit 1; fi
if ! which crm      >/dev/null 2>&1; then echo "Please Install crm"; exit 1; fi
if ! which drbdadm  >/dev/null 2>&1; then echo "Please Install drbd"; exit 1; fi
if ! which awk      >/dev/null 2>&1; then echo "Please Install awk"; exit 1; fi
if ! which ssh      >/dev/null 2>&1; then echo "Please Install openssh"; exit 1; fi
if ! which lvcreate >/dev/null 2>&1; then echo "Please Install lvm2"; exit 1; fi
if ! which rsync    >/dev/null 2>&1; then echo "Please Install rsync"; exit 1; fi
if ! which mktemp   >/dev/null 2>&1; then echo "Please Install mktemp"; exit 1; fi
if ! which ipcalc   >/dev/null 2>&1; then echo "Please Install ipcalc"; exit 1; fi

BROADCAST=$(ipcalc $IP/$IF_LAN_NM | awk '$1 ~ /^Netmask:$/ {print $2}')
. $LIHASSOURCEDIR/usr/lib/cluster-tools-lihas/drbd-functions.sh
DRBDVERSION=$(drbdversion)

if [ ga$5 == ga ]; then
  # Naechstes freies DRBD
  DRBD=$(drbdnextfree)
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

drbdprimaryforce vs_$VSNAME

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

cat <<EOF | crm configure
primitive res_drbd_drbd$DRBD_$VSNAME ocf:linbit:drbd \
        params drbd_resource="vs_$VSNAME" \
        operations \$id="res_drbd_drbd$VSNAME-operations" \
        op start interval="0" timeout="240" \
        op promote interval="0" timeout="90" \
        op demote interval="0" timeout="90" \
        op stop interval="0" timeout="100" \
        op monitor interval="10" timeout="20" start-delay="0" \
        op notify interval="0" timeout="90"
ms ms_$VSNAME res_drbd_drbd$DRBD_$VSNAME \
        meta notify="true" migration-threshold="10"
primitive res_fs_$VSNAME ocf:heartbeat:Filesystem \
        params device="/dev/drbd$DRBD" directory="$VSERVER_BASE/$VSNAME" fstype="ext4" options="noatime,stripe=64,barrier=0" \
        operations \$id="res_fs_$VSNAME-operations" \
        op start interval="0" timeout="600" \
        op stop interval="0" timeout="60" \
        op monitor interval="20" timeout="40" start-delay="0" \
        op notify interval="0" timeout="60"
primitive res_IPaddr2_ip_$VSNAME ocf:heartbeat:IPaddr2 \
        params ip="$IP" nic="$IF_LAN" cidr_netmask="$IF_LAN_NM" broadcast="$BROADCAST" \
        operations \$id="res_IPaddr2_ip_$VSNAME-operations" \
        op start interval="0" timeout="20" \
        op stop interval="0" timeout="20" \
        op monitor interval="10" timeout="20" start-delay="0"
primitive res_VServer-lihas_vs_$VSNAME ocf:lihas:VServer-lihas \
        params vservername="$VSNAME" \
        operations \$id="res_VServer-lihas_vs_$VSNAME-operations" \
        op start interval="0" timeout="600" \
        op stop interval="0" timeout="180" \
        op monitor interval="10" timeout="20" start-delay="5"
group grp_$VSNAME res_fs_$VSNAME res_IPaddr2_ip_$VSNAME res_VServer-lihas_vs_$VSNAME
colocation col_grp_$VSNAME-ms_$VSNAME inf: grp_$VSNAME ms_$VSNAME:Master
order ord_ms_$VSNAME-grp_$VSNAME inf: ms_$VSNAME:promote grp_$VSNAME:start
commit
EOF

if [ "x$VSHOOKPOST" != "x" ]; then
  export VSNAME
  export IP
  export SIZE
  export CONTEXT
  $VSHOOKPOST
fi
