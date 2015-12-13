#!/usr/bin/env bash

echo "*********************************************************************"
echo "Begin DevStack Exercise: VM with NIC ($0)"
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
source $TESTS_DIR/openstack-admin.sh

# Import zone functions
source $TESTS_DIR/snabb-functions.sh


# Instance type to create
INSTANCE_TYPE=m1.zone

# Boot this image
DEFAULT_IMAGE_NAME="Ubuntu 14.04"
DEFAULT_IMAGE_FILE=${DEFAULT_IMAGE_FILE:-"$TOP_DIR/trusty-server-cloudimg-amd64-disk1.img"}

# Security group name
SECGROUP=${SECGROUP:-test_secgroup}

# Instance name
VM_NAME1="vm1"

# ZONE network and port names
ZONE_NET_NAME1="1"
ZONE_PORT_GBPS1="2.5"
ZONE_PORT_ZONE1="1"
ZONE_NETWORK_CIDR1="0::0/64"

# Max timeout for pings
PING_TIMEOUT=60

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
glance image-create --name "$DEFAULT_IMAGE_NAME" --is-public True --disk-format qcow2 --container-format bare --file "$DEFAULT_IMAGE_FILE"

# List the images available
glance image-list

# Grab the id of the image to launch
IMAGE=$(glance image-list | egrep " $DEFAULT_IMAGE_NAME " | get_field 1)
die_if_not_set $LINENO IMAGE "Failure getting image $DEFAULT_IMAGE_NAME"

# Clean-up from previous runs
delete_instance $VM_NAME1
delete_secgroup $SECGROUP
delete_net $ZONE_NET_NAME1


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
ZONE_PORT_ID1=$(create_zone_port_no_security $ZONE_NET_NAME1 $ZONE_NETWORK_CIDR1 $ZONE_PORT_GBPS1 $ZONE_PORT_ZONE1)

# Private net-id
PRIVATE_NET_ID=`_get_net_id $PRIVATE_NETWORK_NAME`
die_if_not_set $LINENO PRIVATE_NET_ID "Failure getting private net-id $PRIVATE_NETWORK_NAME"

# Boot instance
# -------------
VM_UUID=$(boot_instance $VM_NAME1 $INSTANCE_TYPE $IMAGE $SECGROUP $PRIVATE_NET_ID $ZONE_PORT_ID1)

# Check
check_zone_port_binding $ZONE_PORT_ID1 $ZONE_PORT_GBPS1

# Get the instance IP
IP=$(get_and_ping_ip $VM_UUID)

# Clean up
# --------

# Delete instance
delete_instance $VM_UUID

# Delete net
delete_net $ZONE_NET_NAME1

# Delete secgroup
nova secgroup-delete $SECGROUP || die $LINENO "Failure deleting security group $SECGROUP"

set +o xtrace
echo "*********************************************************************"
echo "SUCCESS: End DevStack Exercise: $0"
echo "*********************************************************************"
