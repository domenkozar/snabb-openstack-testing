# functions-zone - Common functions used by DevStack components


# Checks an environment variable is not set or has length 0 OR if the
# exit code is non-zero and prints "message" and exits
# NOTE: env-var is the variable name without a '$'
# die_if_not_set $LINENO env-var "message"
function die_if_not_set {
    local exitcode=$?
    FXTRACE=$(set +o | grep xtrace)
    set +o xtrace
    local line=$1; shift
    local evar=$1; shift
    if ! is_set $evar || [ $exitcode != 0 ]; then
        die $line "$*"
    fi
    $FXTRACE
}


# Grab a numbered field from python prettytable output
# Fields are numbered starting with 1
# Reverse syntax is supported: -1 is the last field, -2 is second to last, etc.
# get_field field-number
function get_field {
    while read data; do
        if [ "$1" -lt 0 ]; then
            field="(\$(NF$1))"
        else
            field="\$$(($1 + 1))"
        fi
        echo "$data" | awk -F'[ \t]*\\|[ \t]*' "{print $field}"
    done
}


function zone_prereq {
    # create the flavor
    if [[ ! $(nova flavor-list | grep $INSTANCE_TYPE | get_field 1) ]]; then
        nova flavor-create $INSTANCE_TYPE 999 1024 10 1
    fi

    nova flavor-key $INSTANCE_TYPE set hw:mem_page_size=large
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

    ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
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
        neutron subnet-list | grep $net_id | awk '{print $2}' | xargs -I% neutron subnet-delete %
        neutron net-delete $net_id
    done
}

function delete_secgroup {
    local secgroup_name=$1
    for secgroup_id in `neutron security-group-list -c id -c name | grep $secgroup_name | awk '{print $2}'`;do
        neutron security-group-delete $secgroup_id
    done
}
