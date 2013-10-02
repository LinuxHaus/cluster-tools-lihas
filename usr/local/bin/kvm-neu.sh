#!/bin/bash

[ -e /etc/cluster-tools-lihas.conf ] && . /etc/cluster-tools-lihas.conf

if [ ga$2 == ga ]; then
  echo "usage: $0 KVMNAME SIZE [DRBDNUM]" >&2
  echo "  z.B. $0 test01 30G" >&2
  echo "  z.B. $0 test01 30G 3" >&2
  exit 1
fi

KVMNAME=$1
SIZE=$2
VIRSHINSTANCES="qemu:///system qemu+ssh://$HOST2/system"
. $LIHASSOURCEDIR/usr/lib/cluster-tools-lihas/drbd-functions.sh
DRBDVERSION=$(drbdversion)

# IF Abfragen nach dem installierten Software, die benoetigt wird
if !([ -e /usr/bin/which ]) ; then echo "which ist nicht installiert!!!"; exit 1; fi
if !([ -e $(which parted) ]) ; then echo "Please Install parted"; exit 1; fi
if !([ -e $(which crm) ]) ; then echo "Please Install crm"; exit 1; fi
if !([ -e $(which drbdadm) ]) ; then echo "Please Install drbd"; exit 1; fi
if !([ -e $(which awk) ]) ; then echo "Please Install awk"; exit 1; fi
if !([ -e $(which sort) ]) ; then echo "Please Install sort"; exit 1; fi
if !([ -e $(which tail) ]) ; then echo "Please Install tail"; exit 1; fi
if !([ -e $(which printf) ]) ; then echo "Please Install printf"; exit 1; fi
if !([ -e $(which ssh) ]) ; then echo "Please Install openssh"; exit 1; fi
if !([ -e $(which lvcreate) ]) ; then echo "Please Install lvm2"; exit 1; fi
if !([ -e $(which rsync) ]) ; then echo "Please Install rsync"; exit 1; fi
if !([ -e $(which mktemp) ]) ; then echo "Please Install mktemp"; exit 1; fi
if !([ -e $(which virsh) ]) ; then echo "Please Install libvirt-bin"; exit 1; fi

if [ ga$3 == ga ]; then
  DRBD=$(drbdnextfree)
else
  DRBD=$3
fi

DRBDPORT=$(printf "%02i" $DRBD)

DUMMY=10

lvcreate -L$SIZE -n kvm_$KVMNAME $VG1
ssh $HOST2 lvcreate -L$SIZE -n kvm_$KVMNAME $VG2

cat <<-EOF > /etc/drbd.d/kvm_$KVMNAME.res
resource kvm_$KVMNAME {  
        protocol        C;
        syncer {
                rate    2000M;
        }
	startup {
		become-primary-on both;
	}
	net {
		allow-two-primaries;
		after-sb-0pri discard-zero-changes;
		after-sb-1pri discard-secondary;
		after-sb-2pri disconnect;
	}
        on $HOST1 {
                device          /dev/drbd$DRBD;
                disk            /dev/$VG1/kvm_$KVMNAME;
                flexible-meta-disk      internal;
                address         $IP_DRBD1:77$DRBDPORT;
        }
        on $HOST2 {
                device          /dev/drbd$DRBD;
                disk            /dev/vg_$HOST2/kvm_$KVMNAME;
                flexible-meta-disk      internal;
                address         $IP_DRBD2:77$DRBDPORT;
        }
}
EOF

rsync -rlHpogDtSvx /etc/drbd.d $HOST2:/etc/
yes yes | drbdadm create-md kvm_$KVMNAME
drbdadm up kvm_$KVMNAME
ssh $HOST2 "(yes yes | drbdadm create-md kvm_$KVMNAME && drbdadm up kvm_$KVMNAME)"

drbdprimaryforce $DRBDVERSION kvm_$KVMNAME
parted /dev/drbd$DRBD mklabel msdos

cat <<EOF | crm configure
primitive p_$KVMNAME ocf:linbit:drbd \
        params drbd_resource="kvm_$KVMNAME" \
        op start interval="0" timeout="240" \
        op promote interval="0" timeout="90" \
        op demote interval="0" timeout="90" \
        op stop interval="0" timeout="100" \
        op monitor interval="10" timeout="20" start-delay="0" \
        op notify interval="0" timeout="90" \
        meta target-role="started"
ms ms_$KVMNAME p_$KVMNAME \
        meta master-max="2" clone-max="2" notify="true" interleave="true"
commit
EOF

while ! drbd-overview | sed 's/:/ /g' | awk '$2 ~ /^kvm_'$KVMNAME'$/' | grep -q Primary/Primary; do
  cat /proc/drbd
  sleep 5
done

virsh pool-create-as --name $KVMNAME --type disk --source-path dev --source-dev /dev/drbd$DRBD --target /dev/
virsh pool-dumpxml $KVMNAME > /etc/libvirt/storage/$KVMNAME.xml
ln -s /etc/libvirt/storage/$KVMNAME.xml /etc/libvirt/storage/autostart/$KVMNAME.xml
ssh $HOST2 /etc/init.d/libvirt-bin stop
rsync -rlHpogDtSvx --numeric-ids /etc/libvirt $HOST2:/etc/
ssh $HOST2 /etc/init.d/libvirt-bin start
/etc/init.d/libvirt-bin restart

DOMFILE=`mktemp`
cat <<-EOF >$DOMFILE
<domain type='kvm' id='3'>
  <name>$KVMNAME</name>
  <uuid>e48d949d-ea81-4ad8-a2b4-56127cd392$DRBDPORT</uuid>
  <memory>524288</memory>
  <currentMemory>524288</currentMemory>
  <vcpu>1</vcpu>
  <os>
    <type arch='x86_64' machine='pc-0.12'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm</emulator>
    <disk type='block' device='disk'>
      <driver name='qemu' type='raw'/>
      <source dev='/dev/drbd$DRBD'/>
      <target dev='hda' bus='virtio'/>
      <alias name='virtio-disk0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </disk>
    <interface type='bridge'>
      <mac address='52:54:00:38:81:$DRBDPORT'/>
      <source bridge='br0'/>
      <target dev='vnet1'/>
      <model type='virtio'/>
      <alias name='net0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <input type='mouse' bus='ps2'/>
    <graphics type='vnc' port='59$DRBDPORT' autoport='no' listen='0.0.0.0'/>
    <video>
      <model type='cirrus' vram='9216' heads='1'/>
      <alias name='video0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <alias name='balloon0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </memballoon>
  </devices>
</domain>
EOF

for virshinstance in $VIRSHINSTANCES; do
  virsh -c $virshinstance define $DOMFILE
done
rm $DOMFILE

cat <<EOF | crm configure
primitive res_VirtualDomain_kvm_$KVMNAME ocf:heartbeat:VirtualDomain \
        params config="/etc/libvirt/qemu/$KVMNAME.xml" \
        op start interval="0" timeout="90" \
        op stop interval="0" timeout="90" \
        op monitor interval="10" timeout="30" start-delay="0" \
        op migrate_from interval="0" timeout="60" \
        op migrate_to interval="0" timeout="120" \
        meta target-role="stopped" \
        meta allow-migrate="true"
colocation col_res_VirtualDomain_kvm_$KVMNAME-ms_$KVMNAME inf: res_VirtualDomain_kvm_$KVMNAME ms_$KVMNAME:Master
order ord_ms_$KVMNAME-res_VirtualDomain_kvm_$KVMNAME inf: ms_$KVMNAME:promote res_VirtualDomain_kvm_$KVMNAME:start
commit
EOF

echo "Dinge tun, z.B. Bootmedium auswaehlen"

