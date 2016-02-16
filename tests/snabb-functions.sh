# functions-zone - Common functions used by DevStack components

TERMINATE_TIMEOUT=120
ASSOCIATE_TIMEOUT=120
PRIVATE_NETWORK_NAME="public"

# Max timeout for pings
PING_TIMEOUT=360
SSH_TIMEOUT=360


# Some of these functions were copied from DevStack source

function ping_check {
    local from_net=$1
    local ip=$2
    local timeout_sec=$3
    local expected=${4:-"True"}
    local check_command=""
    probe_cmd=`_get_probe_cmd_prefix $from_net`
    if [[ "$expected" = "True" ]]; then
        check_command="while ! ping -w 1 -c 1 $ip; do sleep 1; done"
    else
        check_command="while ping -w 1 -c 1 $ip; do sleep 1; done"
    fi
    if ! timeout $timeout_sec sh -c "$check_command"; then
        if [[ "$expected" = "True" ]]; then
            die $LINENO "[Fail] Couldn't ping server"
        else
            die $LINENO "[Fail] Could ping server"
        fi
    fi
}


function _get_net_id {
    neutron net-list | grep $1 | awk '{print $2}'
}

function _get_probe_cmd_prefix {
    local from_net="$1"
    net_id=`_get_net_id $from_net`
    probe_id=`neutron-debug probe-list -c id -c network_id | grep $net_id | awk '{print $2}' | head -n 1`
    echo "ip netns exec qprobe-$probe_id"
}


# wait until port can be reached or timeout with an error
function wait_for_port {
    local ip="$1"
    local port="$2"

    if ! timeout $SSH_TIMEOUT sh -c "while ! nc -z $ip $port; do sleep 0.5; done"; then
        die $LINENO "SSH at $ip:$port timedout after $timeout_sec"
    fi
}


# Get ip of instance
function get_instance_ip {
    local vm_id=$1
    local network_name=$2
    local nova_result="$(nova show $vm_id)"
    local ip=$(echo "$nova_result" | grep "$network_name" | get_field 2)
    if [[ $ip = "" ]];then
        echo "$nova_result"
        die $LINENO "[Fail] Coudn't get ipaddress of VM"
    fi
    echo $ip
}


function zone_prereq {
    # create the flavor
    if [[ ! $(nova flavor-list | grep $INSTANCE_TYPE | get_field 1) ]]; then
        nova flavor-create $INSTANCE_TYPE 999 1024 8 1
    fi
    nova flavor-key $INSTANCE_TYPE set hw:mem_page_size=large
    nova flavor-key $INSTANCE_TYPE set hw:numa_nodes=1

    nova keypair-delete SSH_KEY || true
    nova keypair-add --pub_key ~/.ssh/id_rsa.pub SSH_KEY
}

# Boot an instance (for zone_test_*)
#
# ``$1`` - VM name
# ``$2`` - VM instance type
# ``$3`` - VM image name
# ``$4`` - security group name
# ``$5`` - management/private net-id
# ``$6`` - optional port-ids to add (can be multiple)
#
function boot_instance_vmuid {
    local vm_name=$1
    local instance_type=$2
    local image=$3
    local secgroup=$4
    local net_id=$5

    shift 5
    local nics
    local port_ids
    for port_id in $@; do
        nics="$nics --nic port-id=$port_id"
        port_ids="$port_ids $port_id"
    done

    local vm_boot_cmd="nova boot --flavor $instance_type \
                      --image $image \
                      --key-name SSH_KEY \
                      --security-groups=$secgroup \
                      --nic net-id=$net_id \
                      $nics $vm_name"

    local vm_uuid=$( $vm_boot_cmd | grep ' id ' | get_field 2)
    die_if_not_set $LINENO vm_uuid "Failure launching $vm_name"

    for id in $port_ids; do
        >&2 neutron port-show $id
    done

    echo $vm_uuid
}

function boot_instance {
    local vm_uuid=$(boot_instance_vmuid $@)

    # Check that the status is active within ACTIVE_TIMEOUT seconds
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show $vm_uuid | grep status | grep -q ACTIVE; do sleep 2; done"; then
        die $LINENO "VM didn't become active!"
    fi

    echo $vm_uuid
}

function delete_instance {
    local vm_uuid=$1
    local vm_name=$(nova list | grep $vm_uuid | get_field 2)

    nova delete $vm_uuid || true
    # Wait for termination
    if ! timeout $TERMINATE_TIMEOUT sh -c "while nova list | grep -q $vm_uuid; do sleep 1; done"; then
        die $LINENO "Server $vm_name not deleted"
    fi
}

function create_zone_net {
    local net=$1
    local seg_id=$2
    NET_ID=$(neutron net-create $net --provider:network_type zone --provider:segmentation-id $seg_id --router:external=True | grep ' id ' | get_field 2)
    echo $NET_ID
}

function is_ipv4 {
    local ip=$(echo "$1" | awk '/[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*/ {print $1}')
    if [[ "a$ip" == "a" ]]; then
        return 1
    fi
    return 0
}

function create_zone_port {
    local net_name=$1
    local network_cidr=$2
    local gbps=$3
    local seg=$4
    local extra=${5:-"--security-group $SECGROUP"}

    local zone_net_id=$(neutron net-list -c id -c name | awk '$4=='"$net_name"'{ print $2 }')
    if [[ -z "$zone_net_id" ]]; then
        zone_net_id=`create_zone_net $net_name $seg`
        die_if_not_set $LINENO zone_net_id "Failure creating net $net_name with segment $seg"

        local version=''
        local start=''
        local end=''
        if ! is_ipv4 $network_cidr; then
            version=6
            start=${network_cidr/::0\/64/::10}
            end=${network_cidr/::0\/64/::ffff}
        else
            version=4
            start=${network_cidr/.0\/24/.10}
            end=${network_cidr/.0\/24/.200}
        fi
        >&2 neutron subnet-create --ip_version $version --allocation-pool start=$start,end=$end --no-gateway --disable-dhcp $zone_net_id $network_cidr
    fi

    local zone_subnet_id=$(neutron subnet-list -c id -c network_id | grep $zone_net_id | get_field 1 )
    die_if_not_set $LINENO zone_subnet_id "Failure creating subnet with net-id $zone_net_id"

    local zone_port_id=$(neutron port-create $zone_net_id --binding:profile type=dict zone_gbps=$gbps $extra| grep " id " | get_field 2)
    die_if_not_set $LINENO zone_port_id "Failure creating port with net-id $zone_net_id"

    echo "$zone_port_id"
}

function create_zone_port_no_security {
    create_zone_port $@ --no-security-groups
}

function create_sec_rule {
    local sec_rule_args=$@

    local sec_rule_cmd="neutron security-group-rule-create $sec_rule_args"

    local sec_rule_uuid=$( $sec_rule_cmd | grep ' id ' | get_field 2)
    die_if_not_set $LINENO sec_rule_uuid "Failure creating $sec_rule_args"

    echo $sec_rule_uuid
}

function delete_sec_rule {
    local sec_rule_uuid=$1
    neutron security-group-rule-delete $sec_rule_uuid
}

function check_zone_port_binding {
    local port_id=$1
    local gbps=$2

    local vif_type=$(neutron port-show $port_id | grep "vif_type" | get_field 2)
    local vif_details=$(neutron port-show $port_id | grep "vif_details" | get_field 2)

    # verify vif_type
    if  [ "$vif_type" != "vhostuser" ]; then
        die $LINENO "vif_type=$vif_type is not 'vhostuser'"
    fi

    # verify vif_details
    local zone_gbps=$(echo $vif_details | jshon -e zone_gbps)

    #correct jshon floating point bug
    zone_gbps=$(awk "BEGIN { print ($zone_gbps/10000)*10000}")
    if [ "$zone_gbps" != "$gbps" ]; then
        die $LINENO "vif_details=$vif_details does not have zone_gpbs=$gbps"
    fi
}

function check_zone_port_binding_tunnel {
    local port_id=$1

    local binding_profile=$(neutron port-show $port_id | grep "binding:profile" | get_field 2)

    local tunnel_type=$(echo $binding_profile | jshon -e tunnel_type)
    if [ $tunnel_type != \"L2TPv3\" ]; then
        die $LINENO "Failed binding:profile=$binding_profile"
    fi
}

function clear_zone_port {
    local port_id=$1

    neutron port-delete $port_id || \
        die $LINENO "Failure deleting port $port_id"
}

function get_ip {
    local vm_uuid=$1

    # Get the instance IP
    local ip=$(get_instance_ip $vm_uuid $PRIVATE_NETWORK_NAME)
    die_if_not_set $LINENO ip "Failure retrieving IP address"

    echo $ip
}

function get_and_ping_ip {
    local vm_uuid=$1

    # Get the instance IP
    local ip=$(get_ip $vm_uuid)

    # Private IPs can be pinged in single node deployments
    ping_check "$PRIVATE_NETWORK_NAME" $ip $PING_TIMEOUT >/dev/null 2>&1

    echo $ip
}

function get_zone_port_ip {
    local port_id=$1

    local vif_details=$(neutron port-show $port_id | grep "vif_details" | get_field 2)
    local zone_port_ip=$(echo $vif_details | jshon -e zone_ip)
    die_if_not_set $LINENO zone_port_ip "Failure retrieving zone IP address"

    # remove prefix/suffis double quote
    zone_port_ip="${zone_port_ip%\"}"
    zone_port_ip="${zone_port_ip#\"}"

    echo $zone_port_ip
}

function ip_execute_cmd {
    local ip=$1
    local cmd="$2"
    SSH_USER=${SSH_USER:-ubuntu}

    wait_for_port $ip 22

    ssh -tt -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
}

function vm_execute_cmd {
    local vm_uuid=$1
    local cmd="$2"

    # Get the instance IP
    local ip=$(get_instance_ip $vm_uuid $PRIVATE_NETWORK_NAME)
    die_if_not_set $LINENO ip "Failure retrieving IP address"

    return $(ip_execute_cmd "$ip" "$cmd")
}

function delete_net {
    local net_name=$1
    local net_ids=$(neutron net-list -c id -c name | awk '$4=='"$net_name"'{ print $2 }')
    for net_id in $net_ids;do
        # we have to clear zone ports before net is deleted otherwise we get an error
        for subnet_id in $(neutron net-list | grep $net_id | get_field 3 |  awk '{print $1}'); do
            for port_id in $(neutron port-list | grep $subnet_id | get_field 1); do
                clear_zone_port $port_id
            done
        done
        neutron net-delete $net_id
    done
}


function delete_secgroup {
    local secgroup_name=$1
    for secgroup_id in `neutron security-group-list -c id -c name | grep $secgroup_name | awk '{print $2}'`;do
        neutron security-group-delete $secgroup_id
    done
}
