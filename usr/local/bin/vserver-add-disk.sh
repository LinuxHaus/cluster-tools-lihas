#!/bin/bash

[ -e /etc/cluster-tools-lihas.conf ] && . /etc/cluster-tools-lihas.conf

if [ ga$3 == ga ]; then
  echo "usage: $0 VSNAME MNTPOINT SIZE [DRBDNUM]" >&2
  echo "usage: $0 test01 /var/lib/mysql 10G 115" >&2
  echo "usage: $0 test01 /var/lib/mysql 10G 115 3" >&2
  exit 1
fi

VSNAME=$1
MNTPOINT=$2
SIZE=$3

if [ ga$4 == ga ]; then
  # Naechstes freies DRBD
  DRBD=$(($(awk '$1 ~ /^device$/ && $2 ~ /^\/dev\/drbd/ {gsub(";","",$2); gsub("/dev/drbd","",$2); print $2}' /etc/drbd.d/*.res | sort -un| tail -1)+1))
else
  DRBD=$4
fi

DRBDPORT=$(printf "%02i" $DRBD)

DUMMY=10

RESNAME=vs_$VSNAME$(sed 's#/#_#g' <<< $MNTPOINT)

lvcreate -L$SIZE -n $RESNAME vg_$HOST1
ssh $HOST2 lvcreate -L$SIZE -n $RESNAME vg_$HOST2

cat <<-EOF > /etc/drbd.d/$RESNAME.res
resource $RESNAME {  
        protocol        C;
        syncer {
                rate    2000M;
        }
        on $HOST1 {
                device          /dev/drbd$DRBD;
                disk            /dev/$VG1/$RESNAME;
                flexible-meta-disk      internal;
                address         $IP_DRBD1:77$DRBDPORT;
        }
        on $HOST2 {
                device          /dev/drbd$DRBD;
                disk            /dev/$VG2/$RESNAME;
                flexible-meta-disk      internal;
                address         $IP_DRBD2:77$DRBDPORT;
        }
}
EOF

rsync -rlHpogDtSvx /etc/drbd.d $HOST2:/etc/
yes yes | drbdadm create-md $RESNAME
drbdadm up $RESNAME
ssh $HOST2 "(yes yes | drbdadm create-md $RESNAME && drbdadm up $RESNAME)"

drbdadm -- -o primary $RESNAME

mkfs.ext4 -L $RESNAME /dev/drbd$DRBD
mount /dev/drbd$DRBD /mnt
mv $VSERVER_BASE/$VSNAME$MNTPOINT/. /mnt/
umount /mnt 

cat <<EOF | crm configure
primitive p_$RESNAME ocf:linbit:drbd \
        params drbd_resource="$RESNAME" \
        op start interval="0" timeout="240" \
        op promote interval="0" timeout="90" \
        op demote interval="0" timeout="90" \
        op stop interval="0" timeout="100" \
        op monitor interval="10" timeout="20" start-delay="0" \
        op notify interval="0" timeout="90" \
        meta target-role="started"
ms ms_$RESNAME p_$RESNAME \
        meta clone-max="2" notify="true"
commit
EOF

cat <<EOF | crm configure
primitive res_fs_$RESNAME ocf:heartbeat:Filesystem \
        params device="/dev/drbd$DRBD" directory="$VSERVER_BASE/$VSNAME$MNTPOINT" fstype="ext4" options="noatime,stripe=64,barrier=0" \
        operations \$id="res_$RESNAME-operations" \
        op start interval="0" timeout="600" \
        op stop interval="0" timeout="60" \
        op monitor interval="20" timeout="40" start-delay="0" \
        op notify interval="0" timeout="60" \
        meta is-managed="false"
commit
EOF

EDITOR="sed -i '/^group grp_'$VSNAME'/,/[^\\]/{s/ res_VServer/ res_'$RESNAME' res_VServer/}'" crm configure edit
crm configure manage res_fs_$RESNAME

