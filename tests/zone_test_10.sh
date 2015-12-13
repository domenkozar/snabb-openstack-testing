#!/usr/bin/env bash

# **zone_test_10.sh** - VM with NIC, invalid zone

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

# Security group name
SECGROUP=${SECGROUP:-test_secgroup}

# Instance name
VM_NAME1="vm1"

# ZONE network and port names
ZONE_NET_NAME="1"
ZONE_PORT_GBPS="2.5"
ZONE_PORT_ZONE="9999"
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

#add the image
glance image-create --name "$DEFAULT_IMAGE_NAME" --visibility public --disk-format qcow2 --container-format bare --file "$DEFAULT_IMAGE_FILE"

# List the images available
glance image-list

# Grab the id of the image to launch
IMAGE=$(glance image-list | egrep " $DEFAULT_IMAGE_NAME " | get_field 1)
die_if_not_set $LINENO IMAGE "Failure getting image $DEFAULT_IMAGE_NAME"

# Clean-up from previous runs
delete_instance $VM_NAME1
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

# Private net-id
PRIVATE_NET_ID=`_get_net_id $PRIVATE_NETWORK_NAME`
die_if_not_set $LINENO PRIVATE_NET_ID "Failure getting private net-id $PRIVATE_NETWORK_NAME"

# Boot instance
# -------------
VM_UUID=$(boot_instance_vmuid $VM_NAME1 $INSTANCE_TYPE $IMAGE $SECGROUP $PRIVATE_NET_ID $ZONE_PORT_ID1)

if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show $VM_UUID | grep status | grep -q ERROR; do sleep 2; done"; then
    die $LINENO "VM became active, while it shouldn't!"
fi

# Clean up
# --------

# Delete zone net and port
clear_zone_port $ZONE_PORT_ID1

# Delete instance
delete_instance $VM_UUID

# Delete net
delete_net $ZONE_NET_NAME

# Delete secgroup
nova secgroup-delete $SECGROUP || \
    die $LINENO "Failure deleting security group $SECGROUP"

set +o xtrace
echo "*********************************************************************"
echo "SUCCESS: End DevStack Exercise: $0"
echo "*********************************************************************"
