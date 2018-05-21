#!/usr/bin/env bash

set -eux
set -o pipefail

# locate source files
source="${BASH_SOURCE[0]}"
while [ -h "${source}" ]; do
  srcdir="$( cd -P "$( dirname "${source}" )" && pwd )"
  source="$(readlink "${source}")"
  [[ ${source} != /* ]] && source="${srcdir}/${source}"
done
srcdir="$( cd -P "$( dirname "${source}" )" && pwd )"

devtgz="${srcdir}/devs.tar.gz"

debootstrap_dir="${srcdir}/debootstrap"

[ "${UBUNTU_URI:=}" ] || UBUNTU_URI=https://mirrors.kernel.org/ubuntu/

# reset umask
umask 0022

# check for device file archive
if [ ! -f "${devtgz}" ] ; then
  printf 'missing the /dev tar archive (run sudo mkdev.sh)\n' 1>&2
  exit 2
fi

# create a scratch directory to use for working files
wkdir=$(env TMPDIR=/var/tmp mktemp -d)
export TMPDIR="${wkdir}"

__cleanup () {
  sudo rm -rf "${wkdir}"
}

trap __cleanup EXIT ERR

sudo () { env "$@"; }
# if we're not root, bring sudo to $sudo
[ "$(id -u)" != "0" ] && sudo () { command sudo env "$@"; }

create_chroot_tarball () {
  local packagemanager distribution release subdir
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"
  local gpg_keydir
  # check that we have a gpg dir for dist.
  gpg_keydir="${subdir}/gpg-keys"
  # shellcheck disable=SC2015
  [ ! -d "${gpg_keydir}" ] && { echo "missing ${gpg_keydir}" 1>&2 ; exit 1 ; } || true
  local deboostrap_file
  debootstrap_file="${debootstrap_dir}/scripts/${release}"

  # if we didn't get packagemanager, distribution display usage
  # shellcheck disable=SC2015
  case "${packagemanager}" in
    *yum) packagemanager=yum ;;
    *dnf) packagemanager=dnf ;;
    *apt) packagemanager=apt ; [ ! -e "${debootstrap_file}" ] && { echo "missing ${debootstrap_file}" 1>&2 ; exit 1 ; } || true ;;
    *) echo "unknown packagemanager" 1>&2 ; exit 240 ;;
  esac

  # mock out commands via function overload here - which is exactly what we want, but drives shellcheck batty.
  # shellcheck disable=SC2032,SC2033
  rpm() { sudo rpm --root "${rootdir}" "${@}"; }
  debootstrap() { sudo DEBOOTSTRAP_DIR="$(pwd)/debootstrap" bash -x "$(which debootstrap)" --verbose --arch=amd64 "${@}" "${rootdir}" "${UBUNTU_URI}" ; }

  # let's go!
  rootdir=$(mktemp -d)
  conftar=$(mktemp --tmpdir conf.XXX.tar)

  case "${packagemanager}" in
    yum|dnf)
      # init rpm, add gpg keys and release rpm
      rpm --initdb
      for gpg in "${gpg_keydir}"/* ; do
        rpm --import "${gpg}"
      done
      rpm -iv --nodeps "${subdir}/*.rpm"
      centos_ver=$(rpm -q --qf "%{VERSION}" centos-release || true)
      repos_d=( "${subdir}/yum.repos.d"/*.repo )
      if [ -e "${repos_d[0]}" ] ; then
        for f in "${repos_d[@]}" ; do
          b="${f##*/}"
          sudo install -m644 "${f}" "${rootdir}/etc/yum.repos.d/${b}"
        done
      fi
      case "${distribution}" in
        centos*)
          inst_packages=(@Base yum yum-plugin-ovl yum-utils centos-release) ;;
        fedora*)
          inst_packages=("@Minimal Install" dnf fedora-release fedora-release-notes fedora-gpg-keys)
      esac
      case "${centos_ver}" in
        5) sed -e 's/,nocontexts//' < config/yum-common.conf | sudo tee "${rootdir}/etc/yum.conf" > /dev/null
           inst_packages=(@Base yum yum-utils centos-release centos-release-notes) ;;
        *)
          sudo cp config/yum-common.conf "${rootdir}/etc/yum.conf" ;;
      esac
      # let yum do the rest of the lifting
      sudo rm -rf /var/tmp/yum-* /var/cache/yum/*
      yumconf=$(mktemp --tmpdir yum.XXXX.conf)
      sudo cp "${rootdir}/etc/yum.conf" "${yumconf}"
      printf 'reposdir=%s\n' "${rootdir}/etc/yum.repos.d" >> "${yumconf}"
      sudo yum --releasever="${release}" --installroot="${rootdir}" -c "${yumconf}" repolist -v
      sudo yum --releasever="${release}" --installroot="${rootdir}" -c "${yumconf}" install -q -y "${inst_packages[@]}"
    ;;
    apt)
      keyring=( "${subdir}/gpg-keys"/*.gpg )
      debootstrap --foreign --keyring="${keyring[0]}" "${release}" || true
      sudo mkdir -p --mode=0755 "${rootdir}/var/lib/resolvconf" && sudo touch "${rootdir}/var/lib/resolvconf/linkified"
      [ -f "${subdir}/sources.list" ] && sudo install -m644 "${subdir}/sources.list" "${rootdir}/apt-sources.list"
      case "${distribution}" in
        ubuntu*) sudo mkdir -p --mode=0755 "${rootdir}/usr/share/keyrings" && sudo install -m644 "${keyring[0]}" "${rootdir}/usr/share/keyrings/ubuntu-archive-keyring.gpg" ;;
      esac
    ;;
  esac

  # I need sudo for _read_ permissions, but you can own this fine.
  # shellcheck disable=SC2024
  sudo tar cp '--exclude=./dev*' -C "${rootdir}" . > "${distribution}-${release}.tar"

  # create config tar
  scratch=$(mktemp -d --tmpdir "$(basename "$0")".XXXXXX)
  mkdir -p             "${scratch}"/etc/sysconfig
  chmod a+rx           "${scratch}"/etc/sysconfig
  case "${packagemanager}" in
    yum)
  mkdir -p --mode=0755 "${scratch}"/var/cache/yum
    ;;
  esac
  cp       startup.sh  "${scratch}"/startup
  mkdir -p --mode=0755 "${scratch}"/var/cache/ldconfig
  printf 'NETWORKING=yes\nHOSTNAME=localhost.localdomain\n' > "${scratch}"/etc/sysconfig/network
  printf '127.0.0.1   localhost localhost.localdomain\n'    > "${scratch}"/etc/hosts
  tar --numeric-owner --group=0 --owner=0 -c -C "${scratch}" --files-from=- -f "${conftar}" << EOA || true
./etc/hosts
./etc/sysconfig/network
./var/cache/yum
./var/cache/ldconfig
./startup
EOA

  # uncompress dev tar
  devtar=$(mktemp --tmpdir dev.XXX.tar)
  zcat "${devtgz}" > "${devtar}"

  rpmdbfiles=$(mktemp --tmpdir "$(basename "$0")".XXXXXX)

  case "${packagemanager}" in
    yum|dnf)
      # use this for rpmdb extraction
      cat << EOA > "${rpmdbfiles}"
./var/lib/rpm/Packages
./var/lib/rpm/Name
./var/lib/rpm/Basenames
./var/lib/rpm/Group
./var/lib/rpm/Requirename
./var/lib/rpm/Providename
./var/lib/rpm/Conflictname
./var/lib/rpm/Obsoletename
./var/lib/rpm/Triggername
./var/lib/rpm/Dirnames
./var/lib/rpm/Installtid
./var/lib/rpm/Sigmd5
./var/lib/rpm/Sha1header
EOA

    rpmdbdir=$(mktemp -d --tmpdir "$(basename "$0")".XXXXXX)
    # first, pry the rpmdb out.
    tar -C "${rpmdbdir}" --extract --file="${distribution}-${release}".tar --files-from="${rpmdbfiles}"
    # conver db files to dump files
    for x in "${rpmdbdir}"/var/lib/rpm/* ; do
      /usr/lib/rpm/rpmdb_dump "${x}" > "${x}.dump"
      rm "${x}"
    done

    awk '{printf "%s.dump\n",$0}' < "${rpmdbfiles}" | tar --numeric-owner --group=0 --owner=0 -C "${rpmdbdir}" --create --file="${distribution}-${release}"-rpmdb.tar --files-from=-
    ;;
  esac

  tar --delete --file="${distribution}-${release}".tar --files-from=- << EOA || true
./usr/lib/locale
./usr/share/locale
./lib/gconv
./lib64/gconv
./bin/localedef
./sbin/build-locale-archive
./usr/share/man
./usr/share/doc
./usr/share/info
./usr/share/gnome/help
./usr/share/cracklib
./usr/share/i18n
./var/cache/yum
./sbin/sln
./var/cache/ldconfig
./etc/ld.so.cache
./etc/sysconfig/network
./etc/hosts
./etc/hosts.rpmnew
./etc/yum.conf.rpmnew
./etc/yum/yum.conf
./builddir
$(cat "${rpmdbfiles}")
EOA

  # bring it all together
  tar --concatenate --file="${distribution}-${release}".tar "${devtar}"
  tar --concatenate --file="${distribution}-${release}".tar "${conftar}"
  case "${packagemanager}" in
    yum|dnf) tar --concatenate --file="${distribution}-${release}.tar" "${distribution}-${release}-rpmdb.tar" && rm "${distribution}-${release}-rpmdb.tar" ;;
  esac
}

docker_init () {
  local packagemanager distribution release subdir
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"
  docker import "${distribution}-${release}.tar" "pre/${distribution}-${release}"
  rm "${distribution}-${release}.tar"
  docker run -i --name "setup_${distribution}-${release}" -t "pre/${distribution}-${release}" /startup
  docker export "setup_${distribution}-${release}" | docker import - "build/${distribution}-${release}"
  docker rm "setup_${distribution}-${release}"
  docker rmi "pre/${distribution}-${release}"

  docker_check "build/${distribution}-${release}" "${packagemanager}" && {
    docker tag "build/${distribution}-${release}" "stage2/${distribution}-${release}"
    docker rmi "build/${distribution}-${release}"
  }
}

docker_check () {
  local packagemanager image
  image="${1}"
  packagemanager="${2}"

  case "${packagemanager}" in
    yum|dnf) docker run --rm=true "${image}" "${packagemanager}" check-update ;;
    apt) docker run --rm=true "${image}" bash -ec '{ export TERM=dumb ; apt-get -q update && apt-get -qs dist-upgrade; }' ;;
    *)   echo "don't know how to ${packagemanager}" 1>&2 ; exit 1 ;;
  esac
}

check_existing () {
  [ "${FORCE_BUILD:=}" ] && return 1
  local packagemanager distribution release subdir
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"

  if [ "${DOCKER_SINK:=''}" ] ; then
    docker_check "${DOCKER_SINK}/${distribution}:${release}" "${packagemanager}" && \
      docker tag "${DOCKER_SINK}/${distribution}:${release}" "final/${distribution}:${release}"
  else
    docker rmi -f "${DOCKER_SINK}/${distribution}:${release}"
    return 1
  fi
}

add_layers () {
  local packagemanager distribution release subdir stage2name
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"

  stage2name=$(docker images "stage2/${distribution}-${release}" --format "{{.Repository}}")

  if [ ! -z  "${stage2name}" ] ; then
    if [ -f "${subdir}/Dockerfile" ] ; then
      docker build -f "${subdir}/Dockerfile" -t "final/${distribution}:${release}" .
    else
      docker tag "stage2/${distribution}-${release}" "final/${distribution}:${release}"
    fi
    docker rmi "stage2/${distribution}-${release}"
  fi
}

if [ -z "${1+x}" ] ; then
  # build everything!
  for d in config/*/* ; do
   check_existing "${d}" || {
     create_chroot_tarball "${d}"
     docker_init "${d}"
     add_layers "${d}"
   }
  done
else
  create_chroot_tarball "${1}"
  docker_init "${1}"
  add_layers "${1}"
fi

