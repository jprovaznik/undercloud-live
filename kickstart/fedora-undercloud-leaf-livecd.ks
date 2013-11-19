# Fedora TripleO Undercloud

%include /usr/share/spin-kickstarts/fedora-livecd-xfce.ks

# Need bigger / partition than default
part / --size 6144 --fstype ext4

# rabbitmq doesn't start when selinux is enforcing
selinux --permissive

# we need a network to setup the undercloud
network --activate --device=eth0 --bootproto=dhcp --hostname=ucl-leaf-live

##############################################################################
# Packages
##############################################################################
%packages

git
python-pip

%end
##############################################################################


##############################################################################
# Post --nochroot
##############################################################################
%post --nochroot

cd $INSTALL_ROOT/root
git clone https://github.com/jprovaznik/undercloud-live
cd undercloud-live
git checkout stackuser

%end
##############################################################################


##############################################################################
# Post
##############################################################################
%post --log /opt/stack/kickstart.log --erroronfail

set -ex

export PATH=:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

# We need to be able to resolve addresses
echo nameserver 8.8.8.8 > /etc/resolv.conf

# Add a cache for pip
mkdir -p /var/cache/pip
export PIP_DOWNLOAD_CACHE=/var/cache/pip

# Install the undercloud
/root/undercloud-live/bin/install-leaf.sh

## move diskimage-builder cache into stack user's home dir so it can be reused
## during image builds.
#mkdir -p /home/stack/.cache
#mv /root/.cache/image-create /home/stack/.cache/
#mkdir -p /home/stack/.cache/image-create/yum
#mkdir -p /home/stack/.cache/image-create/ccache
#chown -R stack.stack /home/stack/.cache

# setup users to be able to run sudo with no password
sed -i "s/# %wheel/%wheel/" /etc/sudoers

# tmpfs mount dirs for:
# /var/lib/nova/instances
export NOVA_ID=`id -u nova`
export NOVA_GROUP_ID=`id -g nova`
cat << EOF >> /etc/fstab
tmpfs /var/lib/nova/instances tmpfs rw,uid=$NOVA_ID,gid=$NOVA_GROUP_ID 0 0
EOF

# we need grub2 back (removed by dib elements)
yum -y install grub2-tools grub2 grub2-efi

# Empty root password (easier to debug)
passwd -d root

# Switch over to use iptables instead of firewalld
# This is needed by os-refresh-config
# systemctl mask firewalld
ln -s '/dev/null' '/etc/systemd/system/firewalld.service'

touch /etc/sysconfig/iptables
# systemctl enable iptables
ln -s '/usr/lib/systemd/system/iptables.service' '/etc/systemd/system/basic.target.wants/iptables.service'
# systemctl enable ip6tables
ln -s '/usr/lib/systemd/system/ip6tables.service' '/etc/systemd/system/basic.target.wants/ip6tables.service'

# enable sshd
ln -s '/usr/lib/systemd/system/sshd.service' '/etc/systemd/system/multi-user.target.wants/sshd.service'

# If mounted causes the iso creation to fail
umount /run/netns || true

%end
##############################################################################
