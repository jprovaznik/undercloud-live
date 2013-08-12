#!/bin/bash

set -eux

os=redhat

sudo chown $USER.$USER $HOME/.cache

if [ -e /opt/stack/undercloud-live/.undercloud-init ]; then
    echo undercloud-init has already run, exiting.
    exit
fi

# the current user needs to always connect to the system's libvirt instance
# when virsh is run
sudo cat >> /etc/profile.d/virsh.sh <<EOF

# Connect to system's libvirt instance
export LIBVIRT_DEFAULT_URI=qemu:///system

EOF

# ssh configuration
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -b 1024 -N '' -f ~/.ssh/id_rsa
fi

if [ ! -f ~/.ssh/authorized_keys ]; then
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
fi

sudo service libvirtd restart
sudo service openvswitch restart

grep libvirtd /etc/group || sudo groupadd libvirtd
if ! id | grep libvirtd; then
    echo "adding $USER to group libvirtd"
   sudo usermod -a -G libvirtd $USER

   if [ "$os" = "redhat" ]; then
       libvirtd_file=/etc/libvirt/libvirtd.conf
       if ! sudo grep "^unix_sock_group" $libvirtd_file > /dev/null; then
           sudo sed -i 's/^#unix_sock_group.*/unix_sock_group = "libvirtd"/g' $libvirtd_file
           sudo sed -i 's/^#auth_unix_rw.*/auth_unix_rw = "none"/g' $libvirtd_file
           sudo sed -i 's/^#unix_sock_rw_perms.*/unix_sock_rw_perms = "0770"/g' $libvirtd_file
           sudo service libvirtd restart
       fi
    fi

    exec sudo su -l $USER
fi

/opt/stack/tripleo-incubator/scripts/setup-network

sudo cp /root/stackrc $HOME/undercloudrc

# run os-refresh-config to apply the configuration
sudo os-refresh-config

touch /opt/stack/undercloud-live/.undercloud-init
