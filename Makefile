APPNAME=$(shell basename `pwd`)
VERSION=$(shell git describe | sed 's/-/./g')

UPLOADURL=http://ftp.lihas.de/cgi-bin/newpackage-generic
ARCH=all
COPYRIGHT=2012-2014 Adrian Reyer <are@lihas.de>
DEBIAN_FULL_NAME=Adrian Reyer
DEBIAN_EMAIL=are@lihas.de
DEBIAN_HOMEPAGE=https://github.com/LinuxHaus/firewall-lihas/
DEBIAN_SOURCE=https://github.com/LinuxHaus/firewall-lihas/
DEBIAN_SECTION=admin
DESC_SHORT=Tools to manage clusters
DESC_LONG=Tools to create vserver/lxc/kvm on lvm/drbd-clusters based\n\
on heartbeat/corosync/openais/pacemaker as long as 'crm' works.\n\
Exchange ssh-keys, edit /etc/ha.d/ha.cf, edit\n\
/etc/cluster-tools-lihas.conf and create volumegroups as\n\
vg_\$hostname to make the tools work.\n\
Also, heartbeat-daemon has to be up and running.\n\
Works with corossync as well, needs 'crm'
DEBIAN_DEPENDS=heartbeat2-scripts-lihas, ipcalc
DEBIAN_RECOMMENDS=debootstrap, xmlstarlet
DEBIAN_SUGGESTS=util-vserver-build, pacemaker | crmsh | openais, drbd8-utils, libvirt-bin, liblchown-perl

CFGDDIR=$(DESTDIR)/etc/cluster-tools-lihas.d
CFGDIR=$(DESTDIR)/etc/
CRONDFILES=$( etc/cron.d/* )
CRONHOURLYFILES=$( etc/cron.hourly/* )
CRONDAILYFILES=$( etc/cron.daily/* )
CRONWEEKLYFILES=$( etc/cron.weekly/* )
CRONMONTHLYFILES=$( etc/cron.monthly/* )
BINDIR=$(DESTDIR)/bin
SBINDIR=$(DESTDIR)/sbin
UBINDIR=$(DESTDIR)/usr/bin
USBINDIR=$(DESTDIR)/usr/sbin
ULBINDIR=$(DESTDIR)/usr/local/bin
ULSBINDIR=$(DESTDIR)/usr/local/sbin
ULIBDIR=$(DESTDIR)/usr/lib/$(APPNAME)
USHAREDIR=$(DESTDIR)/usr/share/$(APPNAME)
USDOCDIR=$(DESTDIR)/usr/share/doc/$(APPNAME)
MAN1DIR=$(DESTDIR)/usr/share/man/man1
MAN2DIR=$(DESTDIR)/usr/share/man/man2
MAN3DIR=$(DESTDIR)/usr/share/man/man3
MAN4DIR=$(DESTDIR)/usr/share/man/man4
MAN5DIR=$(DESTDIR)/usr/share/man/man5
MAN6DIR=$(DESTDIR)/usr/share/man/man6
MAN7DIR=$(DESTDIR)/usr/share/man/man7
MAN8DIR=$(DESTDIR)/usr/share/man/man8
RUNDIR=$(DESTDIR)/var/lib/$(APPNAME)

all:

install:
	install -d -m 755 $(UBINDIR)
	install -d -m 755 $(USDOCDIR)
	install -d -m 755 $(ULIBDIR)
	install -d -m 755 $(CFGDIR)
	install -d -m 755 $(MAN8DIR)
	install -D -m 644 etc/cluster-tools-lihas.conf $(CFGDIR)/
	install -D -m 644 doc/*.8 $(MAN8DIR)/
	install -D -m 755 usr/bin/* $(UBINDIR)/
	install -D -m 755 usr/lib/cluster-tools-lihas/* $(ULIBDIR)/
	chown -R root:root $(DESTDIR)
	git log --decorate=short > $(USDOCDIR)/CHANGELOG

#package:
#	cd ../ ; jonixbuild cluster-tools-lihas

debian-clean:
	rm -rf debian
debian-preprepkg:
	if test -d debian ; then echo "ERROR: debian directory already exists"; exit 1; fi

debian-prepkg: debian-preprepkg
	echo | DEBFULLNAME="$(DEBIAN_FULL_NAME)" dh_make -sy --native -e "$(DEBIAN_EMAIL)" -p $(APPNAME)_$(VERSION)
	sed -i 's#^Homepage:.*#Homepage: $(DEBIAN_HOMEPAGE)#; s#^Architecture:.*#Architecture: $(ARCH)#; /^#/d; s#^Description:.*#Description: $(DESC_SHORT)#; s#^ <insert long description, indented with spaces># $(DESC_LONG)#; s#^Depends: .*#Depends: $${misc:Depends},$(DEBIAN_DEPENDS)#; s#^Section: .*#Section: $(DEBIAN_SECTION)#; s#^Standards-Version: .*#Standards-Version: 3.9.6#; /^Depends:/aRecommends: $(DEBIAN_RECOMMENDS)\nSuggests: $(DEBIAN_SUGGESTS)' debian/control
	sed -i 's/^Copyright:.*/Copyright: $(COPYRIGHT)/; /likewise for another author/d; s#^Source:.*#Source: $(DEBIAN_SOURCE)#; /^#/d' debian/copyright
	rm debian/*.ex debian/README.Debian debian/README.source debian/*.doc-base.EX
	for file in /etc/cluster-tools-lihas.conf; do echo $i >> debian/conffiles; done

debian-dpkg:
	dpkg-buildpackage -sa -rfakeroot -tc

debian-dpkg-nosign:
	dpkg-buildpackage -sa -rfakeroot -tc -us -uc

debian-upload:
	curl -u `cat $(HOME)/.debianrepositoryauth` -v $(UPLOADURL) -F B1="Datei hochladen" -F uploaded_file=@../$(APPNAME)_$(VERSION)_$(ARCH).deb -F dists="wheezy,jessie,stretch"
