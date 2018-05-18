FROM stage2/centos-6

RUN yum -y install epel-release

ADD pki/rpm-gpg /etc/pki/rpm-gpg
ADD yum.repos.d /etc/yum.repos.d

RUN yum -y install tar
