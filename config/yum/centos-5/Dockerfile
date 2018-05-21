FROM stage2/centos-5

ADD pki/rpm-gpg /etc/pki/rpm-gpg
ADD pki/rpm-gpg-centos-5 /etc/pki/rpm-gpg

RUN yum -q -y install curl.x86_64 epel-release && \
    rm -f /etc/yum.repos.d/epel.repo.rpmnew
