{ system ? builtins.currentSystem }:

with import <nixpkgs/nixos/lib/testing.nix> { inherit system; };
with import <nixpkgs/lib>;


makeTest {
  nodes = {
    allinone = { config, pkgs, lib, ... }:
    {
      require = [ (import ./openstack.nix).allinone ];
      virtualisation.memorySize = 2560;
      virtualisation.diskSize = 2 * 1024;
      virtualisation.qemu.options = ["-device pci-assign,host=84:00.1"];
    };
  };

  testScript = ''
    startAll;

    # wait for all services to start
    $allinone->waitForUnit("keystone-all.service");
    $allinone->waitForUnit("glance-api.service");
    $allinone->waitForUnit("neutron-server.service");
    $allinone->waitForUnit("nova-api.service");

    # finish bridge networking on the host
    $allinone->execute('ip link add eth1 type veth peer name eth2')
    $allinone->execute('ifconfig eth2 203.0.113.1 up')'

    # setup openstack resources
    $allinone->execute('source bootstrap.sh')

    subtest "VM with NIC ", sub {
      $allinone->execute('./tests/zone_test_01.sh')
    }
  '';
}
