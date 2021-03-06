{
  network.description = "Test OpenStack Libery";

  allinone = { config, pkgs, lib, ... }:
    let
      sshKeys = pkgs.runCommand "ssh-keys" {} ''
        mkdir -p $out
        ${pkgs.openssh}/bin/ssh-keygen -q -N "" -f $out/id_rsa
      '';
    ubuntuImage = pkgs.fetchurl {
      url = "http://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img";
      sha256 = "1qppjr762jsvg0azdv5avmqxdpc9nwprjvvfvg7ipwvmgcdz405f";
    };
    centosImage = pkgs.fetchurl {
      url = "http://cloud.centos.org/centos/7/devel/CentOS-7-x86_64-GenericCloud.qcow2";
      sha256 = "08i9pp6bw6q649dzc6sz5ddn895h00g5xf577fzhps6qksc0kzr4";
    };
    bootstrap_sh = pkgs.writeText "bootstrap-openstack.sh" ''
      set -xe

      # Keystone

      ## Create a temporary setup account
      export OS_TOKEN=SuperSecreteKeystoneToken
      export OS_URL=http://localhost:35357/v3
      export OS_IDENTITY_API_VERSION=3

      ## Register keystone service to itself
      openstack service create --name keystone --description "OpenStack Identity" identity
      openstack endpoint create --region RegionOne identity public http://localhost:5000/v2.0
      openstack endpoint create --region RegionOne identity internal http://localhost:5000/v2.0
      openstack endpoint create --region RegionOne identity admin http://controller:35357/v2.0

      ## Create projects, users and roles for admin project
      openstack project create --domain default --description "Admin Project" admin
      openstack user create --domain default --password asdasd admin
      openstack role create admin
      openstack role add --project admin --user admin admin

      ## Create service project
      openstack project create --domain default --description "Service Project" service

      ## Create projects, users and roles for service project
      openstack project create --domain default --description "Demo Project" demo
      openstack user create --domain default --password asdasd demo
      openstack role create user
      openstack role add --project demo --user demo user
      # Allow demo to add private flavors, see https://github.com/dianaclarke/openstack-notes/wiki/openstack-flavors
      openstack role add --user demo --project demo admin

      ## Use admin login
      unset OS_TOKEN
      unset OS_URL
      export OS_PROJECT_DOMAIN_ID=default
      export OS_USER_DOMAIN_ID=default
      export OS_PROJECT_NAME=admin
      export OS_TENANT_NAME=admin
      export OS_USERNAME=admin
      export OS_PASSWORD=asdasd
      export OS_AUTH_URL=http://localhost:35357/v3
      export OS_IDENTITY_API_VERSION=3
      export OS_IMAGE_API_VERSION=2

      ## Verify
      #openstack token issue

      # Glance
      openstack user create --domain default --password asdasd glance
      openstack role add --project service --user glance admin
      openstack service create --name glance --description "OpenStack Image service" image
      openstack endpoint create --region RegionOne image public http://localhost:9292
      openstack endpoint create --region RegionOne image internal http://localhost:9292
      openstack endpoint create --region RegionOne image admin http://localhost:9292

      ## Verify
      #glance image-create --name "nixos" --file {image}/nixos.img --disk-format qcow2 --container-format bare --visibility public
      #glance image-list

      # Nova
      openstack user create --domain default --password asdasd nova
      openstack role add --project service --user nova admin
      openstack service create --name nova --description "OpenStack Compute" compute
      openstack endpoint create --region RegionOne compute public http://localhost:8774/v2/%\(tenant_id\)s
      openstack endpoint create --region RegionOne compute internal http://localhost:8774/v2/%\(tenant_id\)s
      openstack endpoint create --region RegionOne compute admin http://localhost:8774/v2/%\(tenant_id\)s

      ## Verify
      #nova service-list
      #nova endpoints
      #nova image-list

      # Neutron
      openstack user create --domain default --password asdasd neutron
      openstack role add --project service --user neutron admin
      openstack service create --name neutron --description "OpenStack Networking" network
      openstack endpoint create --region RegionOne network public http://localhost:9696
      openstack endpoint create --region RegionOne network internal http://localhost:9696
      openstack endpoint create --region RegionOne network admin http://localhost:9696

      ## Verify
      #neutron ext-list
      #neutron agent-list

      # Create public network
      neutron net-create public --shared --provider:physical_network public --provider:network_type flat
      neutron subnet-create public 203.0.113.0/24 --name public --allocation-pool start=203.0.113.101,end=203.0.113.200 --dns-nameserver 8.8.8.8 --gateway 203.0.113.1

      ## Use Demo account
      export OS_PROJECT_DOMAIN_ID=default
      export OS_USER_DOMAIN_ID=default
      export OS_PROJECT_NAME=demo
      export OS_TENANT_NAME=demo
      export OS_USERNAME=demo
      export OS_PASSWORD=asdasd
      export OS_AUTH_URL=http://localhost:5000/v3
      export OS_IDENTITY_API_VERSION=3
      export OS_IMAGE_API_VERSION=2

      ## Launch an instance
      nova keypair-add --pub-key ${sshKeys}/id_rsa.pub mykey
      #nova keypair-list
      nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
      nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
      #nova boot --flavor m1.tiny --image nixos --security-group default --key-name mykey public-instance

      ifconfig eth1 203.0.113.1 up
    '';
    in {
      # Configure OpenStack
      virtualisation = {
        keystone.enableSingleNode = true;
        glance.enableSingleNode = true;
        neutron.enableSingleNode = true;
        neutron.extraML2Config = ''
          [ml2_snabb]
          zone_definition_file = ${./ml2_zones.conf}
        '';
        nova.enableSingleNode = true;
      };
      networking.extraHosts = ''
        127.0.0.1 controller
        127.0.0.1 allinone
      '';
      networking.localCommands = ''
        ip link add eth0 type veth peer name eth1
      '';

      # Configure Snabb
      require = [ ./snabb.nix ];
      services.snabb.enable = true;
      services.snabb.ports = [
        {
          pci = "0000:00:15.0";
          node = "1";
          cpu = "14";
          portid = "0";
        }
        {
          pci = "0000:00:16.0";
          node = "1";
          cpu = "15";
          portid = "1";
        }
      ];


      # bridge networking setup
      boot.kernel.sysctl = {
        "net.bridge.bridge-nf-call-arptables" = 1;
        "net.bridge.bridge-nf-call-iptables" = 1;
        "net.bridge.bridge-nf-call-ip6tables" = 1;
        "net.bridge.bridge-nf-filter-vlan-tagged" = 0;
        "net.bridge.bridge-nf-filter-pppoe-tagged" = 0;
        # hugepages are a requirement
        "vm.nr_hugepages" = 4096;
      };
      boot.kernelParams = [ "hugepages=4096" ];
      boot.kernelModules = [ "br_netfilter" ];
      boot.extraModprobeConfig = "options kvm-intel nested=y";

      # bridge networking uses dhcp https://github.com/NixOS/nixpkgs/issues/10101
      networking.firewall.enable = false;

      environment.systemPackages = with pkgs.pythonPackages; with pkgs; [
        # OpenStack clients
        openstackclient novaclient glanceclient keystoneclient neutronclient
        neutron
        # activationScripts
        iproute nettools bridge-utils
        # debugging
        #iptables tcpdump ebtables vim pciutils telnet numactl
        # needed by tests
        jshon
      ];

      system.activationScripts.openstack = ''
        cp ${bootstrap_sh} /root/bootstrap.sh
        chmod +x /root/bootstrap.sh
        cp -R ${./tests} /root/tests
        cp ${ubuntuImage} /root/tests/trusty-server-cloudimg-amd64-disk1.img
        cp ${centosImage} /root/tests/CentOS-7-x86_64-GenericCloud.qcow2

        # copy over ssh keys
        mkdir -p /root/.ssh/
        cp ${sshKeys}/id_rsa /root/.ssh/
        chmod 700 /root/.ssh/{,id_rsa}
        cp ${sshKeys}/id_rsa.pub /root/.ssh/
      '';
    };
}
