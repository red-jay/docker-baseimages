#!/bin/bash
set -ex

export DEBIAN_FRONTEND=noninteractive

platform="yum"
type yum || platform=""
[ -f /debootstrap/debootstrap ] && platform="apt"

case "${platform}" in
  yum)
    dbload=/usr/bin/db_load

    # bring RPM back online from export so it works in chroot.
    cd /var/lib/rpm

    for x in *.dump ; do
      cat "${x}" | /usr/lib/rpm/rpmdb_load $(basename "${x}" .dump)
      rm "${x}"
    done

    cd -

    rpm --rebuilddb || [ -d /var/lib/rpmrebuilddb.* ]

    if [ -d /var/lib/rpmrebuilddb.* ] ; then
      mv /var/lib/rpmrebuilddb.*/* /var/lib/rpm
      rmdir /var/lib/rpmrebuilddb.*
    fi

    yum clean all
  ;;
  apt)
    /debootstrap/debootstrap --second-stage || { cat /debootstrap/debootstrap.log ; exit 1; }
    install -m644 /apt-sources.list /etc/apt/sources.list && rm /apt-sources.list
    apt-get update
    apt-get install -qy debsums
    apt-get -qy upgrade
    debsums_init
    apt-get clean all
  ;;
esac

# if we find ourselves, delete ourselves.
if [[ -s "$BASH_SOURCE" ]] && [[ -x "$BASH_SOURCE" ]]; then
        rm $(readlink -f "$BASH_SOURCE")
fi
