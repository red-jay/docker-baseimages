#!/bin/bash
set -ex

export DEBIAN_FRONTEND=noninteractive

platform="yum"
type yum || platform=""
type dnf && platform="dnf"
[ -f /debootstrap/debootstrap ] && platform="apt"

case "${platform}" in
  yum|dnf)
    # bring RPM back online from export so it works in chroot.
    cd /var/lib/rpm

    for x in *.dump ; do
      dest="$(basename "${x}" .dump)"
      /usr/lib/rpm/rpmdb_load "${dest}" < "${x}"
      rm "${x}"
    done

    cd -

    rpm --rebuilddb || { rebuilddbdirs=( /var/lib/rpmrebuilddb.* ) && [ -d "${rebuilddbdirs[0]}" ]
      mv "${rebuilddbdirs[0]}"/* /var/lib/rpm
      rmdir "${rebuilddbdirs[0]}"
    }

    "${platform}" clean all
  ;;
  apt)
    dpkg-divert --rename /usr/bin/ischroot && ln -s /bin/true /usr/bin/ischroot
    dpkg-divert --rename /usr/sbin/invoke-rc.d && ln -s /bin/true /usr/sbin/invoke-rc.d
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections
    /debootstrap/debootstrap --second-stage || { cat /debootstrap/debootstrap.log ; exit 1; }
    install -m644 /apt-sources.list /etc/apt/sources.list && rm /apt-sources.list
    apt-get update
    apt-get --no-install-recommends install -qy debsums ca-certificates
    apt-get -qy dist-upgrade
    debsums_init
    apt-get clean all
    rm -rf /var/lib/apt/lists/*
    rm /usr/bin/ischroot && dpkg-divert --rename --remove /usr/bin/ischroot
    rm /usr/sbin/invoke-rc.d && dpkg-divert --rename --remove /usr/sbin/invoke-rc.d
  ;;
esac

[ ! -d /etc/stamps.d ] && rm -rf /etc/stamps.d && mkdir /etc/stamps.d
date "+%s" > /etc/stamps.d/base.stamp

# if we find ourselves, delete ourselves.
if [[ -s "$BASH_SOURCE" ]] && [[ -x "$BASH_SOURCE" ]]; then
        rm "$(readlink -f "$BASH_SOURCE")"
fi
