#!/usr/bin/env bash


echo "*********************************************************************"
echo "Begin DevStack Exercise: 2xVM with security group restrictions and stateless filtering ($0)"
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
TESTS_DIR=$(cd $(dirname "$0") && pwd)

# Import OpenStack credentials
source $TESTS_DIR/openstack-demo-user.sh

# Get all helper functions in scope
source $TESTS_DIR/functions-common.sh

# Import zone functions
source $TESTS_DIR/snabb-functions.sh

# Instance type to create
INSTANCE_TYPE=m1.zone

# Boot this image
#DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-"Ubuntu 14.04"}
DEFAULT_IMAGE_NAME="Ubuntu 14.04"
DEFAULT_IMAGE_FILE=${DEFAULT_IMAGE_FILE:-"$TESTS_DIR/trusty-server-cloudimg-amd64-disk1.img"}

# Security group name
SECGROUP=${SECGROUP:-test_secgroup}

# Instance name
VM_NAME1="vm1"
VM_NAME2="vm2"

# ZONE network and port names
ZONE_NET_NAME="1"
ZONE_PORT_GBPS="5.5"
ZONE_PORT_ZONE="1"
ZONE_NETWORK_CIDR="0::0/64"

SERVER_PORT=2222

# Max time to wait while vm goes from build to active state
ACTIVE_TIMEOUT=120


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

#add the image
glance image-create --name "$DEFAULT_IMAGE_NAME" --visibility public --disk-format qcow2 --container-format bare --file "$DEFAULT_IMAGE_FILE"

# List the images available
glance image-list

# Grab the id of the image to launch
IMAGE=$(glance image-list | egrep " $DEFAULT_IMAGE_NAME " | get_field 1)
die_if_not_set $LINENO IMAGE "Failure getting image $DEFAULT_IMAGE_NAME"

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
neutron security-group-rule-create --protocol icmp \
    --ethertype ipv4 --direction ingress $SECGROUP
neutron security-group-rule-create --protocol icmp \
    --ethertype ipv6 --direction ingress $SECGROUP

neutron security-group-rule-create --protocol tcp --port-range-min 22 \
    --ethertype ipv4 --port-range-max 22 --direction ingress $SECGROUP

# List secgroup rules
nova secgroup-list-rules $SECGROUP

# Set up instance
# ---------------

# List flavors
nova flavor-list

# Create the zone net, subnet and port
ZONE_PORT_ID1=$(create_zone_port $ZONE_NET_NAME $ZONE_NETWORK_CIDR $ZONE_PORT_GBPS $ZONE_PORT_ZONE)
ZONE_PORT_ID2=$(create_zone_port $ZONE_NET_NAME $ZONE_NETWORK_CIDR $ZONE_PORT_GBPS $ZONE_PORT_ZONE)

# Private net-id
PRIVATE_NET_ID=`_get_net_id $PRIVATE_NETWORK_NAME`
die_if_not_set $LINENO PRIVATE_NET_ID "Failure getting private net-id $PRIVATE_NETWORK_NAME"

# Boot instance
# -------------
VM_UUID1=$(boot_instance $VM_NAME1 $INSTANCE_TYPE $IMAGE $SECGROUP $PRIVATE_NET_ID $ZONE_PORT_ID1)
VM_UUID2=$(boot_instance $VM_NAME2 $INSTANCE_TYPE $IMAGE $SECGROUP $PRIVATE_NET_ID $ZONE_PORT_ID2)

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
ip_execute_cmd $IP2 "sudo ifconfig eth1 up; sudo ip addr add $ZONE_IP2/64 dev eth1"
sleep 10

# SERVER running on VM1 on IP1
ip_execute_cmd $IP1 "while true; do nc -6 -vd -l $SERVER_PORT > /dev/null ; done" &
SERVER_PID=$!
sleep 10

ip_execute_cmd $IP1 "ping6 -c3 $ZONE_IP2"
ip_execute_cmd $IP2 "ping6 -c3 $ZONE_IP1"

if ip_execute_cmd $IP2 "echo \"Test\" | nc -v $ZONE_IP1 $SERVER_PORT"; then
    die $LINENO "Failure port should not be reachable yet"
fi

SEC_RULE_UUID=$(create_sec_rule --ethertype ipv6 \
    --ethertype ipv6 \
    --protocol tcp \
    --port-range-min $SERVER_PORT \
    --port-range-max $SERVER_PORT \
    --direction ingress $SECGROUP)
sleep 10

ip_execute_cmd $IP1 "ping6 -c3 $ZONE_IP2"
ip_execute_cmd $IP2 "ping6 -c3 $ZONE_IP1"

if ! ip_execute_cmd $IP2 "echo \"Test\" | nc -v $ZONE_IP1 $SERVER_PORT"; then
    die $LINENO "Failure port should be reachable"
fi

# disable statefull filtering
neutron port-update $ZONE_PORT_ID1 \
    --binding:profile type=dict zone_gbps=$ZONE_PORT_GBPS,packetfilter=stateless
neutron port-update $ZONE_PORT_ID2 \
    --binding:profile type=dict zone_gbps=$ZONE_PORT_GBPS,packetfilter=stateless
sleep 10

if ip_execute_cmd $IP2 "echo \"Test\" | nc -v $ZONE_IP1 $SERVER_PORT"; then
    die $LINENO "Failure port should not be reachable"
fi

delete_sec_rule $SEC_RULE_UUID

# Clean up
# --------

# kill pending ssh connection
kill -9 $SERVER_PID > /dev/null || true


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
