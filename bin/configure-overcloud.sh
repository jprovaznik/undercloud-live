#!/bin/bash

set -eu

source /opt/stack/undercloud-live/bin/common.sh
source ~/undercloudrc

export OVERCLOUD_IP=$(nova list | grep notcompute.*ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")

source tripleo-overcloud-passwords
source /opt/stack/tripleo-incubator/overcloudrc


wait_for 60 10 ssh_noprompt heat-admin@$OVERCLOUD_IP sudo journalctl -u os-collect-config \| grep \'Completed phase post-configure\'

source /etc/profile.d/tripleo-incubator-scripts.sh

init-keystone \
    -p $OVERCLOUD_ADMIN_PASSWORD \
    $OVERCLOUD_ADMIN_TOKEN \
    $OVERCLOUD_IP \
    admin@example.com \
    heat-admin@$OVERCLOUD_IP

setup-endpoints \
    $OVERCLOUD_IP \
    --cinder-password $OVERCLOUD_CINDER_PASSWORD \
    --glance-password $OVERCLOUD_GLANCE_PASSWORD \
    --heat-password $OVERCLOUD_HEAT_PASSWORD \
    --neutron-password $OVERCLOUD_NEUTRON_PASSWORD \
    --nova-password $OVERCLOUD_NOVA_PASSWORD

user-config

setup-neutron "" "" 10.0.0.0/8 "" "" 192.0.2.45 192.0.2.64 192.0.2.0/24

os-adduser -p $OVERCLOUD_DEMO_PASSWORD demo demo@example.com

nova flavor-delete m1.tiny
nova flavor-create m1.tiny 1 512 2 1

source /opt/stack/tripleo-incubator/overcloudrc-user
user-config
