#!/usr/bin/env bash

# **zone_test_8.sh** - VM with L2TPv3

# Test instance connectivity with the ``nova`` command from ``python-novaclient``

echo "*********************************************************************"
echo "Begin DevStack Exercise: $0"
echo "*********************************************************************"

# This script exits on an error so that errors don't compound and you see
# only the first error that occurred.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following allowing as the install occurs.
set -o xtrace


# Settings
# ========

# Keep track of the current directory
EXERCISE_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=$(cd $EXERCISE_DIR/..; pwd)

# Import common functions
source $TOP_DIR/functions

# Import zone functions
source $TOP_DIR/functions-zone

# Import configuration
source $TOP_DIR/openrc

# Import project functions
source $TOP_DIR/lib/neutron

# Import exercise configuration
source $TOP_DIR/exerciserc

# If nova api is not enabled we exit with exitcode 55 so that
# the exercise is skipped
is_service_enabled n-api || exit 55

# Instance type to create
INSTANCE_TYPE=m1.zone

# Boot this image
#DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-"Ubuntu 14.04"}
DEFAULT_IMAGE_NAME="Ubuntu 14.04"
DEFAULT_IMAGE_FILE=${DEFAULT_IMAGE_FILE:-"$TOP_DIR/trusty-server-cloudimg-amd64-disk1.img"}
L2TP_IMAGE_NAME="Centos 7"
L2TP_IMAGE_FILE="CentOS-7-x86_64-GenericCloud.qcow2"
L2TP_SSH_USER="centos"

# Security group name
SECGROUP=${SECGROUP:-test_secgroup}

# Instance name
VM_NAME1="vm1"
VM_NAME2="vm2"

# ZONE network and port names
ZONE_NET_NAME="1"
ZONE_PORT_GBPS="1"
ZONE_PORT_ZONE="1"
ZONE_NETWORK_CIDR="0::0/64"

# Max timeout for pings
PING_TIMEOUT=60

# Max time to wait while vm goes from build to active state
ACTIVE_TIMEOUT=120

# Cells does not support floating ips API calls
is_service_enabled n-cell && exit 55

# Launching a server
# ==================

# List servers for tenant:
nova list

# Images
# ------

#TODO: get the image if it does not exist

# Check prerequisites
zone_prereq

# delete previously aded image with same name
IMAGE=$(glance image-list | egrep " $DEFAULT_IMAGE_NAME " | get_field 1)
if [[ ! -z "$IMAGE" ]]; then
    glance image-delete $IMAGE
fi
L2TP_IMAGE=$(glance image-list | egrep " $L2TP_IMAGE_NAME " | get_field 1)
if [[ ! -z "$L2TP_IMAGE" ]]; then
    glance image-delete $L2TP_IMAGE
fi

#add the image
glance image-create --name "$DEFAULT_IMAGE_NAME" --is-public True --disk-format qcow2 --container-format bare --file "$DEFAULT_IMAGE_FILE"
glance image-create --name "$L2TP_IMAGE_NAME" --is-public True --disk-format qcow2 --container-format bare --file "$L2TP_IMAGE_FILE"

# List the images available
glance image-list

# Grab the id of the image to launch
IMAGE=$(glance image-list | egrep " $DEFAULT_IMAGE_NAME " | get_field 1)
die_if_not_set $LINENO IMAGE "Failure getting image $DEFAULT_IMAGE_NAME"
L2TP_IMAGE=$(glance image-list | egrep " $L2TP_IMAGE_NAME " | get_field 1)
die_if_not_set $LINENO L2TP_IMAGE "Failure getting image $L2TP_IMAGE_NAME"

# Clean-up from previous runs
delete_instance $VM_NAME1
delete_instance $VM_NAME2
delete_secgroup $SECGROUP
delete_net $ZONE_NET_NAME

# Security Groups
# ---------------
# Create a secgroup
nova secgroup-create $SECGROUP "$SECGROUP description"
if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova secgroup-list | grep -q $SECGROUP; do sleep 1; done"; then
    die $LINENO "Security group not created"
fi

# Configure Security Group Rules
neutron security-group-rule-create --ethertype ipv4 $SECGROUP
neutron security-group-rule-create --ethertype ipv6 $SECGROUP

# List secgroup rules
nova secgroup-list-rules $SECGROUP

# Set up instance
# ---------------

# List flavors
nova flavor-list

# Create the zone net, subnet and port
ZONE_PORT_ID1=$(create_zone_port_no_security $ZONE_NET_NAME $ZONE_NETWORK_CIDR $ZONE_PORT_GBPS $ZONE_PORT_ZONE)
ZONE_PORT_ID2=$(create_zone_port_no_security $ZONE_NET_NAME $ZONE_NETWORK_CIDR $ZONE_PORT_GBPS $ZONE_PORT_ZONE)

# Private net-id
PRIVATE_NET_ID=`_get_net_id $PRIVATE_NETWORK_NAME`
die_if_not_set $LINENO PRIVATE_NET_ID "Failure getting private net-id $PRIVATE_NETWORK_NAME"

# Boot instance
# -------------
VM_UUID1=$(boot_instance $VM_NAME1 $INSTANCE_TYPE $IMAGE $SECGROUP $PRIVATE_NET_ID $ZONE_PORT_ID1)
VM_UUID2=$(boot_instance $VM_NAME2 $INSTANCE_TYPE $L2TP_IMAGE $SECGROUP $PRIVATE_NET_ID $ZONE_PORT_ID2)

# Check
check_zone_port_binding $ZONE_PORT_ID1 $ZONE_PORT_GBPS
check_zone_port_binding $ZONE_PORT_ID2 $ZONE_PORT_GBPS

# Get the instance IP
IP1=$(get_and_ping_ip $VM_UUID1)
ZONE_IP1=$(get_zone_port_ip $ZONE_PORT_ID1)
IP2=$(get_and_ping_ip $VM_UUID2)
ZONE_IP2=$(get_zone_port_ip $ZONE_PORT_ID2)

# SSH to the VM and setup the
ip_execute_cmd $IP1 "sudo ifconfig eth1 up; sudo ip addr add $ZONE_IP1/64 dev eth1"
SSH_USER=$L2TP_SSH_USER ip_execute_cmd $IP2 "sudo ifconfig eth1 up; sudo ip addr add $ZONE_IP2/64 dev eth1"
sleep 10
ip_execute_cmd $IP1 "ping6 -c10 $ZONE_IP2"
SSH_USER=$L2TP_SSH_USER ip_execute_cmd $IP2 "ping6 -c10 $ZONE_IP1"

# L2TP SERVER running on VM2 on IP2
SSH_USER=$L2TP_SSH_USER ip_execute_cmd $IP2 "sudo modprobe l2tp_ip6; sudo modprobe l2tp_eth"
SSH_USER=$L2TP_SSH_USER ip_execute_cmd $IP2 "sudo ip l2tp add tunnel tunnel_id 1 peer_tunnel_id 1 encap ip local $ZONE_IP2 remote $ZONE_IP1"
SSH_USER=$L2TP_SSH_USER ip_execute_cmd $IP2 "sudo ip l2tp add session tunnel_id 1 session_id 0001 peer_session_id 0001 cookie 00000000 peer_cookie 00000000"
SSH_USER=$L2TP_SSH_USER ip_execute_cmd $IP2 "sudo ifconfig l2tpeth0 up"

neutron port-update $ZONE_PORT_ID1 \
    --binding:profile type=dict zone_gbps=$ZONE_PORT_GBPS,tunnel_type=L2TPv3,l2tpv3_next_hop=$ZONE_IP2,l2tpv3_remote_ip=$ZONE_IP2,l2tpv3_session=1,l2tpv3_local_cookie=00000000,l2tpv3_remote_cookie=00000000
sleep 10

ip_execute_cmd $IP1 "sudo ifconfig eth1 1.1.1.1 up"
SSH_USER=$L2TP_SSH_USER ip_execute_cmd $IP2 "sudo ifconfig l2tpeth0 1.1.1.2 up; ping -c10 1.1.1.1"
ip_execute_cmd $IP1 "ping -c10 1.1.1.2"

# Check
check_zone_port_binding_tunnel $ZONE_PORT_ID1

# Clean up
# --------

# Delete instance
delete_instance $VM_UUID1
delete_instance $VM_UUID2

# Delete net
delete_net $ZONE_NET_NAME

# Delete secgroup
nova secgroup-delete $SECGROUP || \
    die $LINENO "Failure deleting security group $SECGROUP"

set +o xtrace
echo "*********************************************************************"
echo "SUCCESS: End DevStack Exercise: $0"
echo "*********************************************************************"
