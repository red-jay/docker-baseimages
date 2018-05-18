FROM stage2/centos-5

ADD pki/rpm-gpg /etc/pki/rpm-gpg
ADD pki/rpm-gpg-centos-5 /etc/pki/rpm-gpg

ADD pki/ca-bundle.crt /etc/pki/tls/certs/ca-bundle.crt

RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-Palantir-Arch && \
    yum -q -y install curl.x86_64 epel-release && \
    rm /etc/yum.repos.d/epel.repo.rpmnew
