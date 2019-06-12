#!/bin/bash
#b8_yang@163.com
bash_path=$(cd "$(dirname "$0")";pwd)
source ./base.config


if [[ "$(whoami)" != "root" ]]; then
	echo "please run this script as root ." >&2
	exit 1
fi

log="./setup.log"  #操作日志存放路径 
fsize=2000000         
exec 2>>$log  #如果执行过程中有错误信息均输出到日志文件中

echo -e "\033[31m 这个是ceph集群一键部署脚本！欢迎关注我的个人公众号“devops的那些事”获得更多实用工具！Please continue to enter or ctrl+C to cancel \033[0m"
sleep 5
#yum update
yum_update(){
	yum update -y
}
#configure yum source
yum_config(){
  yum install wget epel-release -y
#  cd /etc/yum.repos.d/ && mkdir bak && mv -f *.repo bak/
#  wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
#  wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
#  yum clean all && yum makecache
  cat >> /etc/yum.repos.d/ceph.repo << EOF
# [ceph]
# name=ceph
# baseurl=http://mirrors.aliyun.com/ceph/rpm-jewel/el7/x86_64/
# gpgcheck=0
# [ceph-noarch]
# name=cephnoarch
# baseurl=http://mirrors.aliyun.com/ceph/rpm-jewel/el7/noarch/
# gpgcheck=0
[ceph]
name=ceph
baseurl=http://mirrors.163.com/ceph/rpm-jewel/el7/x86_64/
enabled=1
gpgcheck=1
type=rpm-md
gpgkey=https://mirrors.163.com/ceph/keys/release.asc
priority=1
[ceph-noarch]
name=cephnoarch
baseurl=http://mirrors.163.com/ceph/rpm-jewel/el7/noarch
enabled=1
gpgcheck=1
type=rpm-md
gpgkey=https://mirrors.163.com/ceph/keys/release.asc
priority=1
[ceph-source]
name=cephsource
baseurl=http://mirrors.163.com/ceph/rpm-jewel/el7/SRPMS
enabled=1
gpgcheck=1
type=rpm-md
gpgkey=https://mirrors.163.com/ceph/keys/release.asc
priority=1
EOF
  yum -y install iotop iftop openssh-server yum-utils nc net-tools git lrzsz expect gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel wget vim ncurses-devel autoconf automake zlib-devel  python-devel bash-completion
}
#firewalld
iptables_config(){
  systemctl stop firewalld.service
  systemctl disable firewalld.service
  iptables -P FORWARD ACCEPT
}

#system config
system_config(){
  sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
  timedatectl set-local-rtc 1 && timedatectl set-timezone Asia/Shanghai
  yum -y install chrony && systemctl start chronyd.service && systemctl enable chronyd.service
  ntpdate 0.asia.pool.ntp.org
}

ulimit_config(){
  echo "ulimit -SHn 102400" >> /etc/rc.local
  cat >> /etc/security/limits.conf << EOF
  *           soft   nofile       102400
  *           hard   nofile       102400
  *           soft   nproc        102400
  *           hard   nproc        102400
  *           soft  memlock      unlimited 
  *           hard  memlock      unlimited
EOF

}



ssh_config(){

if [`grep 'UserKnownHostsFile' /etc/ssh/ssh_config`];then
echo "pass"
else
sed -i "2i StrictHostKeyChecking no\nUserKnownHostsFile /dev/null" /etc/ssh/ssh_config
fi
}

#set sysctl
sysctl_config(){
  cp /etc/sysctl.conf /etc/sysctl.conf.bak
  cat > /etc/sysctl.conf << EOF
  #docker
  net.bridge.bridge-nf-call-iptables = 1
  net.bridge.bridge-nf-call-ip6tables = 1
  vm.swappiness=0
EOF
  /sbin/sysctl -p
  echo "sysctl set OK!!"
}


get_localip(){
ipaddr='172.0.0.1'
ipaddr=$(ip addr | awk '/^[0-9]+: / {}; /inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}' | grep $ip_segment)
echo "$ipaddr"
}



change_hosts(){
num=0
cd $bash_path
rm -rf new_hostname_list.config
touch new_hostname_list.config
for host in ${hostip[@]}
do
let num+=1
if [ $host = `get_localip` ];then
`hostnamectl set-hostname $hostname$num`

echo $host `hostname` >> /etc/hosts
echo `hostname` >> ./new_hostname_list.config
else
echo $host $hostname$num >> /etc/hosts
echo $hostname$num >> ./new_hostname_list.config
fi
done
}

compute_change_hosts(){
num=0
cd $bash_path
rm -rf compute_hostname_list.config hosts
touch compute_hostname_list.config
for host in ${compute_hostip[@]}
do
let num+=1
#if [ $host != `get_localip` ];then
# `hostnamectl set-hostname $compute_hostname$num`

# echo $host `hostname` >> ./hosts
# echo `hostname` >> ./compute_hostname_list.config
# else
echo $host $compute_hostname$num >> ./hosts
#echo $compute_hostname$num >> ./compute_hostname_list.config
#fi
done
}


rootssh_trust(){
cd $bash_path
for host in `cat ./new_hostname_list.config`
do
if [ `hostname` != $host ];then

if [ ! -f "/root/.ssh/id_rsa.pub" ];then
expect ssh_trust_init.exp $root_passwd $host
else
expect ssh_trust_add.exp $root_passwd $host
fi

echo "$host  install ceph please wait!!!!!!!!!!!!!!! "
scp base.config node_install_ceph.sh new_hostname_list.config  root@$host:/root && scp /etc/hosts root@$host:/etc/hosts && ssh root@$host /root/node_install_ceph.sh
echo "$host install ceph  success!!!!!!!!!!!!!!! "

fi
done
}

compute_trust(){
cd /ceph/my-cluster
for host in ${compute_hostip[@]}
do

#if [ `get_localip` != $host ];then

if [ ! -f "/root/.ssh/id_rsa.pub" ];then
expect $bash_path/ssh_trust_init.exp $root_passwd $host
else
expect $bash_path/ssh_trust_add.exp $root_passwd $host
fi

scp $bash_path/base.config $bash_path/compute_hostname_list.config $bash_path/compute_node_install_ceph.sh root@$host:/root && scp $bash_path/hosts root@$host:/etc/hosts && ssh root@$host /root/compute_node_install_ceph.sh

ceph-deploy install $host
if [ "$?" != 0 ]; then
ceph-deploy purge $host
ssh root@$host "yum install -y python-setuptools yum-plugin-priorities ceph-deploy"
if [ -f "/etc/yum.repos.d/ceph.repo" ];then
yum clean all
rm -rf /etc/yum.repos.d/ceph*
fi

ceph-deploy install $host --repo-url=http://mirrors.aliyun.com/ceph/rpm-jewel/el7/ --gpg-url=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7 
ceph-deploy admin $host
else
ceph-deploy admin $host
fi
echo "$host install ceph  success!!!!!!!!!!!!!!! "
#fi
done
}

#yum_install_ceph
yum_install_ceph(){

yum install -y python-setuptools  yum-plugin-priorities ceph-deploy

}


config_ceph(){
mkdir -p /ceph/my-cluster
cd /ceph/my-cluster
ceph-deploy new `hostname`
cat >> /ceph/my-cluster/ceph.conf << EOF
public network = $public_network
cluster network = $cluster_network
osd pool default size = 3
rbd_default_format = 2
max open files = 131072

[osd]
osd data = /var/lib/ceph/osd/ceph-\$id
 
osd journal size = $journal_size
osd mkfs type = xfs
osd mkfs options xfs = -f
mon_pg_warn_max_per_osd = 1000

filestore xattr use omap = true
filestore min sync interval = 10
filestore max sync interval = 15
filestore queue max ops = 25000
filestore queue max bytes = 10485760
filestore queue committing max ops = 5000
filestore queue committing max bytes = 10485760000
 
journal max write bytes = 1073714824
journal max write entries = 10000
journal queue max ops = 50000
journal queue max bytes = 10485760000
 
osd max write size = 512
osd client message size cap = 2147483648
osd deep scrub stride = 131072
osd op threads = 8
osd disk threads = 4
osd map cache size = 1024
osd map cache bl size = 128
osd mount options xfs = "rw,noexec,nodev,noatime,nodiratime,nobarrier"
osd recovery op priority = 4
osd recovery max active = 10
osd max backfills = 4
 
[client]
rbd cache = true
rbd cache size = 268435456
rbd cache max dirty = 134217728
rbd cache max dirty age = 5
EOF
}

#install_ceph
install_ceph(){
cd /ceph/my-cluster
for hname in `cat $bash_path/new_hostname_list.config`
do
ceph-deploy install $hname
done
}



remove_ceph(){
cd /ceph/my-cluster
for hname in `cat $bash_path/new_hostname_list.config`
do
ceph-deploy purge $hname
#ceph-deploy purgedata $hname
#ceph-deploy forgetkeys 
done
# ceph-deploy purge `hostname`
# ceph-deploy purgedata `hostname`
# ceph-deploy forgetkeys 

echo "################################################ remove_ceph is succeed ########################################"
}

check_status(){
ceph -s
}

mon_admin(){
cd /ceph/my-cluster
ceph-deploy mon create-initial
for hname in `cat $bash_path/new_hostname_list.config`
do
ceph-deploy admin $hname
chmod +r /etc/ceph/ceph.client.admin.keyring
done

}

osd_pool(){
ceph osd pool create $osd_pool_name $osd_pool_size
ceph osd lspools
}


user_libvirt(){
cd /ceph/my-cluster
ceph auth get-or-create client.libvirt mon "allow r" osd "allow class-read object_prefix rbd_children, allow rwx pool=$osd_pool_name"
ceph auth get-key client.libvirt | tee client.libvirt.key
ceph auth get client.libvirt -o ceph.client.libvirt.keyring
cat > secret.xml <<EOF
<secret ephemeral='no' private='no'>
  <uuid>59073e9d-4d58-4569-8c75-dc1cdd6ffe70</uuid>
  <usage type='ceph'>
          <name>client.libvirt secret</name>
  </usage>
</secret>
EOF

}

send_libvirt_file(){
cd /ceph/my-cluster
for hname in ${compute_hostip[@]}
do
scp ceph.client.libvirt.keyring root@$hname:/etc/ceph
scp client.libvirt.key secret.xml root@$hname:/var/lib/one
ssh root@$hname "cd /var/lib/one;virsh -c qemu:///system secret-define secret.xml; virsh -c qemu:///system secret-set-value --secret 59073e9d-4d58-4569-8c75-dc1cdd6ffe70 --base64 \$(cat /var/lib/one/client.libvirt.key)"
done
}


add_monitor(){
number=0
for hname in `cat $bash_path/new_hostname_list.config`
do
let number+=1
if [[ $number -le $monitor_number && `hostname` != $hname ]];then
ceph-deploy mon add $hname
sed -i "s/^mon_initial_members = `hostname`/&,$hname/g" /ceph/my-cluster/ceph.conf
hosts_ip=$(cat /etc/hosts|grep $hname|awk '{print $1}')
sed -i "s/^mon_host = `get_localip`/&,$hosts_ip/g" /ceph/my-cluster/ceph.conf
fi
done

}

install_ceph_repo_url(){
cd /ceph/my-cluster
for hname in `cat $bash_path/new_hostname_list.config`
do
yum install -y python-setuptools yum-plugin-priorities ceph-deploy 
ceph-deploy install $hname --repo-url=http://mirrors.aliyun.com/ceph/rpm-jewel/el7/ --gpg-url=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7 
done
echo "################################################ install_ceph_repo_url is succeed ########################################"
}

ovwewrite_conf(){
cd /ceph/my-cluster
for hname in `cat $bash_path/new_hostname_list.config`
do
ceph-deploy --overwrite-conf config push $hname
done

}


main(){
  #yum_update
  # yum_config
  # ssh_config
  # iptables_config
  # system_config
  # ulimit_config


  # change_hosts
  # rootssh_trust

  
  # yum_install_ceph
  # config_ceph
  # install_ceph
  
# if [ "$?" != 0 ]; then

    # if [ -f "/etc/yum.repos.d/ceph.repo" ];then
    # yum clean all
    # rm -rf /etc/yum.repos.d/ceph*
    # fi

    # remove_ceph
    # install_ceph_repo_url
    # mon_admin
    # check_status
    # else
    # mon_admin
    # check_status
# fi
# if [ $monitor_number -gt 1 ];then
    # add_monitor
    # ovwewrite_conf
# fi
compute_change_hosts
compute_trust
osd_pool
user_libvirt
send_libvirt_file

}
main > ./setup.log 2>&1
