# undercloud-live

Tools and scripts to build an undercloud Live CD and/or configure an already
running Fedora 19 x86_64 system into an undercloud.  

To get started, clone this repo to your home directory:

    $ cd
    $ git clone https://github.com/agroup/undercloud-live.git

### Prerequisites
* Only works on Fedora 19 x86_64
* sudo as root ability

### Caveats
* The system is configured to use the iptables service instead of the firewalld
  service.
* SELinux is set to Permissive mode.  Otherwise, rabbitmq-server will not
  start.
  See: https://bugzilla.redhat.com/show_bug.cgi?id=998682
  Note: we will be switching to use qpid soon

## kickstarts
The kickstart files can be used with livecd-tools to build live images.

1. install spin-kickstarts and livecd-tools if needed

They produce iso's in the current directory from which the below commands are
run.  To test the isos you can do something like:

    qemu-kvm -m 2048 Fedora-Undercloud-LiveCD.iso

### fedora-undercloud-control-livecd.ks
kickstart file that can be used to build an Undercloud Control Live CD.

1. livecd-creator --debug --verbose --title "Fedora Undercloud Control" --fslabel=Fedora-Undercloud-Control-LiveCD --cache=/var/cache/yum/x86_64/19 --releasever=19 --config /path/to/undercloud-live/kickstart/fedora-undercloud-control-livecd.ks -t /tmp/

### fedora-undercloud-leaf-livecd.ks
kickstart file that can be used to build an Undercloud Leaf Live CD.

1. livecd-creator --debug --verbose --title "Fedora Undercloud Leaf" --fslabel=Fedora-Undercloud-Leaf-LiveCD --cache=/var/cache/yum/x86_64/19 --releasever=19 --config /path/to/undercloud-live/kickstart/fedora-undercloud-leaf-livecd.ks -t /tmp/

### Running/Installing (2-node)
The 2-node (control and leaf) version of undercloud-live uses the host's
libvirt instance for the baremetal nodes.  This makes it easier to use vm's for
everythng, but, there is some host setup that needs to be done.

Each step below (where applicable) is prefaced with what system to run it on.
 * HOST - the virtualization host you're using to run vm's
 * CONTROL - undercloud control node
 * LEAF - undercloud leaf node

Commands on the Host can be run as your normal user.

Commands on the Control and Leaf nodes should be run as the stack user unless
specified otherwise.

1. [HOST] Define and use a $TRIPLEO_ROOT directory

        mkdir tripleo
        export TRIPLEO_ROOT=/full/path/to/tripleo
        cd $TRIPLEO_ROOT

1. [HOST] Clone the repositories for tripleo-incubator and undercloud-live.

        git clone https://github.com/openstack/tripleo-incubator
        git clone https://github.com/agroup/undercloud-live
        pushd undercloud-live
        git checkout slagle/package
        popd

1. [HOST] Add the tripleo scripts to your path.

        export PATH=$TRIPLEO_ROOT/tripleo-incubator/scripts:$PATH

1. [HOST] Install necessary packages

        install-dependencies

1. [HOST] Define environment variables for the baremetal nodes.

        export NODE_CPU=1
        export NODE_MEM=2048
        export NODE_DISK=20 
        export NODE_ARCH=amd64

1. [HOST] Ensure that openvswitch is started

        sudo service openvswitch start

1. [HOST] Setup the brbm openvswitch bridge and libvirt network.

        setup-network

1. [HOST] Export LIBVIRT_DEFAULT_URI to prevent undercloud-live using 
   qemu:///system.  Check that the default libvirt connection for your user is 
   qemu:///system. If it is not, set an environment variable to configure the 
   connection. 

        export LIBVIRT_DEFAULT_URI=${LIBVIRT_DEFAULT_URI:-"qemu:///system"} 

1. [HOST] If you needed to set LIBVIRT_DEFAULT_URI in the previous step, create
   a profile script to ensure the environment variable gets set in future
   sessions.  This is needed to ensure the virtual power manager can find
   the baremetal instances created on the host.

        sudo su -c "echo export LIBVIRT_DEFAULT_URI=qemu:///system > /etc/profile.d/virsh.sh"

1. [HOST] Create the baremetal nodes.  Specify the path to your undercloud-live 
   checkout as needed.  Save the output of this command, you will need it later.

        undercloud-live/bin/nodes.sh

1. [HOST] Create a vm for the control node, and one for the leaf node.  There
   are libvirt templates called ucl-control-live and ucl-leaf-live in the
   undercloud-live checkout in the templates directory to *help* with this.
   Review the templates and make any changes you'd like (to increate ram, etc).
   
   One change you may want to make is to add the HOST IP address to the graphics
   definition in each vm. This way you can use a spice client to connect and run
   the installation:

        <graphics type='spice' autoport='yes' listen='10.0.1.25'/>

   Once the vms are up (next steps) you'll be able to use a spice client 
   to connect. You need to first discover the port spice is listening on for
   each vm 

   [NOTE this port is only assigned/available *after* the vm has been started]:

        [HOST]
        virsh dumpxml ucl-control-live
        [root@hostname]# virsh dumpxml ucl-control-live
        ... 
        <graphics type='spice' port='5900' 
        ...

        [yourlaptop]
        yum install spice-gtk-tools-0.18-2.fc18.x86_64
        spicy -h 10.0.1.25 -p 5900

   Repeat the above for ucl-leaf-live.

   Finally note: if you *are* using the above templates, you will note they are
   expecting the Fedora-Undercloud-Control.iso and Fedora-Undercloud-Leaf.iso
   images to be in /var/lib/libvirt/images so make sure you move them there 
   after download and rename or edit the path accordingly. Furthermore, 
   the templates also reference two qcow disk images you will need to create: 
        
        cd /var/lib/libvirt/images
        qemu-img create -f qcow2 ucl-leaf-live.qcow2 40G
        qemu-img create -f qcow2 ucl-control-live.qcow2 40G
        cd $TRIPLEO_ROOT

1. [HOST] Before starting the vm for the leaf node, edit it's libvirt xml and
   add the following as an additional network interface (this is already added
   in the templates above, so if you used those, you don't need to do this
   step).

        <interface type='network'>
            <source network='brbm'/>
            <model type='e1000'/>
        </interface>

1. [HOST] Boot the vm's for the control and leaf nodes from their respective
   iso images. If you are using the templates from above:

        virsh define undercloud-live/templates/ucl-control-live.xml
        virsh define undercloud-live/templates/ucl-leaf-live.xml
        virsh start ucl-control-live
        virsh start ucl-leaf-live

1. [CONTROL],[LEAF] Install the images to disk.
   There is a kickstart file included on the images to make this easier.
   However, before using the kickstart file, first make sure that a network
   configuration script exists for every network interface (this might be
   a Fedora bug).  Here are some example commands that copy network scripts for 
   a system with 1 interface, and a system with 2 interfaces

        # System with 1 interface called ens3
        sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-ens3

        # System with 2 interfaces, ens3 and ens6
        sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-ens3
        sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-ens6
   
1. [CONTROL],[LEAF] Make any needed changes to the kickstart file and then run
   (This should be run as liveuser, not root):

        liveinst --kickstart /opt/stack/undercloud-live/kickstart/anaconda-ks.cfg

1. [CONTROL],[LEAF] Once the install has finished, reboot the control and leaf
   vm's.  Make sure when they reboot, they boot from disk, not iso.  You can
   login with either stack/stack or root/root.

1. [HOST] Add a route from your host to the 192.0.2.0/24 subnet via the leaf
   ip.  Update $LEAF_IP for your environment.

        export LEAF_IP=192.168.122.101
        sudo ip route add 192.0.2.0/24 via $LEAF_IP

1. [CONTROL] Edit /etc/sysconfig/undercloud-live-config and set all
   the defined environment variables in the file.  Remember to set
   $UNDERCLOUD_MACS based on the output from when nodes.sh was run earlier.  
   Refer to
   https://github.com/agroup/undercloud-live/blob/slagle/package/elements/undercloud-environment/install.d/02-undercloud-metdata
   for documentation of the environment variables (documentation was added to
   the file directly in a later commit).

        NOTE: The following may not be obvious variables in 
        the config file:

        #this is the second interface on the leaf node, ens6
        export LEAF_INTERFACE=ens6

        #set libvirt user according to what you used on HOST:
        export LIBVIRT_USER=root

        #the LIBVIRT Host IP will be the IP for virbr0 on HOST, not the
        #'main' host address:
        export LIBVIRT_HOST=192.168.122.1

        The rest should be self explanatory, if not shout!

   Once edited,  run undercloud-metadata
   on the control node to refresh the configuration.


        sudo undercloud-metadata

   Use the command in the output from undercloud-metadata to watch/tail the log
   of os-collect-config.  Make sure it runs successfully once.  You'll be able
   to tell when you see "Completed phase post-configure" in the log.

1. [LEAF] Edit /etc/sysconfig/undercloud-live-config and set all
   the defined environment variables in the file.  
   Refer to
   https://github.com/agroup/undercloud-live/blob/slagle/package/elements/undercloud-environment/install.d/02-undercloud-metdata
   for documentation of the environment variables (documentation was added to
   the file directly in a later commit).
   Once edited,  run undercloud-metadata
   on the control node to refresh the configuration.

   MAKE SURE you set the variables correctly, as mentioned in the previous
   step for CONTROL.

        sudo undercloud-metadata

   Use the command in the output from undercloud-metadata to watch/tail the log
   of os-collect-config.  Make sure it runs successfully once.  You'll be able
   to tell when you see "Completed phase post-configure" in the log.

1. Copy over images, or build them on the control node for the deploy kernel
   and overcloud images.  If you don't provide the images, the next step will
   attempt to create them for you.  You will need the following images to exist
   on the control node.  

        /opt/stack/images/overcloud-control.qcow2
        /opt/stack/images/overcloud-compute.qcow2
        /opt/stack/images/deploy-ramdisk.initramfs
        /opt/stack/images/deploy-ramdisk.kernel

1. [CONTROL] Load the images into glance.

        /opt/stack/undercloud-live/bin/images.sh

1. [CONTROL] Run the script to setup the baremetal nodes, and define
   the baremetal flavor.

        /opt/stack/undercloud-live/bin/baremetal-2node.sh

1. [HOST] Add the configured virtual power host key to ~/.ssh/authorized_keys
   on the host.  Define $LEAF_IP as needed for your environment.

        export LEAF_IP=192.168.122.101
        ssh stack@$LEAF_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys
        chmod 0600 ~/.ssh/authorized_keys

1. [HOST] Ensure that SSH Daemon has started

        sudo service sshd start

1. [CONTROL] Deploy an Overcloud.  If you're deploying the Overcloud to
   baremetal, first edit deploy-overcloud.sh and update $OVERCLOUD_LIBVIRT_TYPE
   to "kvm" instead.  This script writes out the tripleo-overcloud-passwords
   file, so I suggest running it from the stack user's home dir.

        /opt/stack/undercloud-live/bin/deploy-overcloud.sh

1. [CONTROL] Source the undercloudrc file so you can interact with OpenStack
   clients:

        source /etc/sysconfig/undercloudrc

1. [CONTROL] Use heat stack-list to check for the overcloud to finish
   deploying.  It should show CREATE_COMPLETE in the output.

1. [CONTROL] Pull latest undercloud-live.

        cd /opt/stack/undercloud-live
        sudo git pull
        cd

1. [CONTROL] Configure the overcloud.  This performs setup of the overcloud and
   loads a cirros image into overcloud glance.

        /opt/stack/undercloud-live/bin/configure-overcloud.sh

1. [CONTROL] As an overcloud user, launch a cirros image on the overcloud.

        source /etc/sysconfig/undercloudrc
        export OVERCLOUD_IP=$(nova list | grep notcompute.*ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")
        source tripleo-overcloud-passwords
        source /opt/stack/tripleo-incubator/overcloudrc
        curl -L -O https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img
        glance image-create \
            --name user \
            --public \
            --disk-format qcow2 \
            --container-format bare \
            --file cirros-0.3.0-x86_64-disk.img
        source /opt/stack/tripleo-incubator/overcloudrc-user
        nova boot --key-name default --flavor m1.tiny --image user demo
        # nova list until the instance is ACTIVE
        nova list
        PORT=$(neutron port-list -f csv -c id --quote none | tail -n1)
        neutron floatingip-create ext-net --port-id "${PORT//[[:space:]]/}"
        # nova list again to see the assigned floating ip
        nova list

1. [CONTROL] ssh to the instance on the overcloud

        # Use the correct assigned floating ip here
        # cirros user's password is cubswin:)
        ssh cirros@192.0.2.46

### Adding additional Leaf Nodes

You can add additional Leaf Nodes to handle provisioning baremetal nodes in
other subnets/vlans.  There is some manual configuration required however.
These steps show adding a leaf node for a new 192.0.3.0/24 subnet.

1. [HOST] Create a new ovs bridge for the new network for the leaf node.

        sudo ovs-vsctl add-br brbm-2

1. [HOST] Create a libvirt network for the bridge.

        cd $TRIPLEO_ROOT/tripleo-incubator/templates
        cp brbm.xml brbm-2.xml
        sed -i 's/brbm/brbm-2/g' brbm-2.xml
        virsh net-define brbm-2.xml

1. [HOST] Create a new vm template for the additional leaf node.

        cd $TRIPLEO_ROOT/undercloud-live/templates
        cp ucl-leaf-live.xml ucl-leaf-live-2.xml

1. [HOST] Edit ucl-leaf-live-2.xml and make the following changes:
    1. Change the vm name to ucl-leaf-live-2
    1. Change the disk name to ucl-leaf-live-2.qcow2, and don't forget to
       create the disk as well.
    1. Delete the mac address line for the default network
    1. Change the brbm network name to brbm-2
    1. Delete the mac address line for the brbm-2 network.

1. [HOST] Define a vm for the additional leaf node.

        virsh define ucl-leaf-live-2.xml

1. [HOST] Boot the ucl-leaf-live-2 vm from the leaf live iso image.

1. [LEAF] Install the images to disk.
   There is a kickstart file included on the images to make this easier.
   However, before using the kickstart file, first make sure that a network
   configuration script exists for every network interface (this might be
   a Fedora bug).  Here are some example commands that copy network scripts for 
   a system with 1 interface, and a system with 2 interfaces

        # System with 2 interfaces, ens3 and ens6
        sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-ens3
        sudo cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-ens6
   
1. [LEAF] Make any needed changes to the kickstart file and then run
   (This should be run as liveuser, not root):

        liveinst --kickstart /opt/stack/undercloud-live/kickstart/anaconda-ks.cfg

1. [LEAF] Once the install has finished, reboot the control and leaf
   vm's.  Make sure when they reboot, they boot from disk, not iso.  You can
   login with either stack/stack or root/root.

1. [HOST] Add a route from your host to the 192.0.3.0/24 subnet (or whatever
   subnet you're using) via the leaf
   ip.  Update $LEAF_IP for your environment.

        export LEAF_IP=192.168.122.102
        sudo ip route add 192.0.3.0/24 via $LEAF_IP

1. [CONTROL] Add a route from the undercloud control node to the new subnet via
   the new leaf node's IP.

        export LEAF_IP=192.168.122.102
        sudo ip route add 192.0.3.0/24 via $LEAF_IP

1. [LEAF] Edit /opt/stack/os-config-refresh/pre-configure.d/97-fedora-iptables
   and add the following line *before* the call to iptables-save:

        iptables -I FORWARD -d 192.0.3.0/24 -j ACCEPT

1. [LEAF] Delete the OK file for 97-fedora-iptables so the rules get applied
   again.

        sudo rm -f /opt/stack/boot-stack/fedora-iptables.ok
        
1. [LEAF] Edit /etc/sysconfig/undercloud-live-config and set all
   the defined environment variables in the file.  
   Refer to
   https://github.com/agroup/undercloud-live/blob/slagle/package/elements/undercloud-environment/install.d/02-undercloud-metdata
   for documentation of the environment variables (documentation was added to
   the file directly in a later commit).
   
   When setting LEAF_DNSMASQ_IP, use 192.0.3.1, or whatever corresponds to the
   subnet you're setting up the leaf node for.

   When setting LEAF_SERVICE_HOST, use undercloud-leaf-2, or a different unique
   value among the leaf nodes.

   Once edited,  run undercloud-metadata
   on the control node to refresh the configuration.

        sudo undercloud-metadata

   Use the command in the output from undercloud-metadata to watch/tail the log
   of os-collect-config.  Make sure it runs successfully once.  You'll be able
   to tell when you see "Completed phase post-configure" in the log.

1. [LEAF] Edit /lib/systemd/system/nova-bm-dnsmasq.service and update the dhcp
   range in the call to dnsmasq from 192.0.2.xxx to 192.0.3.xxx.  The updated
   call to dnsmasq would look something like:

        ExecStart=/sbin/dnsmasq --conf-file= --port=0 --enable-tftp --tftp-root=/tftpboot --dhcp-boot=pxelinux.0 \
                        --pid-file=/var/run/dnsmasq.pid --interface=br-ctlplane --dhcp-range=192.0.3.65,192.0.3.69,29

1. [LEAF] Restart the nova-bm-dnsmasq service.

        sudo systemctl restart nova-bm-dnsmasq

1. [CONTROL] Add a new subnet for 192.0.3.0/24 to the ctlplane network

        source /etc/sysconfig/undercloudrc
        TENANT_ID=$(keystone tenant-list | grep ' admin ' | awk '{print $2}')
        neutron subnet-create --tenant-id $TENANT_ID ctlplane 192.0.3.0/24

1. [HOST] Add the configured virtual power host key to ~/.ssh/authorized_keys
   on the host.  Define $LEAF_IP as needed for your environment.

        export LEAF_IP=192.168.122.102
        ssh stack@$LEAF_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys
        chmod 0600 ~/.ssh/authorized_keys

1. [CONTROL] You can add baremetal nodes associated with this new leaf node
   using the nova command directly from the undercloud control node.

        source /etc/sysconfig/undercloudrc
        # undercloud-leaf-2 is the value of LEAF_SERVICE_HOST
        nova baremetal-node-create undercloud-leaf-2 1 2048 20 52:54:00:4e:76:e1


# References
