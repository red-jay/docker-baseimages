#!/bin/bash
set -ex

export DEBIAN_FRONTEND=noninteractive

platform="yum"
type yum || platform=""
[ -f /debootstrap/debootstrap ] && platform="apt"

case "${platform}" in
  yum)
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

    yum clean all
  ;;
  apt)
    /debootstrap/debootstrap --second-stage || { cat /debootstrap/debootstrap.log ; exit 1; }
    install -m644 /apt-sources.list /etc/apt/sources.list && rm /apt-sources.list
    apt-get update
    apt-get install -qy debsums ca-certificates
    apt-get -qy upgrade
    debsums_init
    apt-get clean all
  ;;
esac

# if we find ourselves, delete ourselves.
if [[ -s "$BASH_SOURCE" ]] && [[ -x "$BASH_SOURCE" ]]; then
        rm "$(readlink -f "$BASH_SOURCE")"
fi
