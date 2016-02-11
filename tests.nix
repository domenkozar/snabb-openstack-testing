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
      virtualisation.qemu.options = optionals (builtins.getEnv "SKIP_PCI" == "") [
        "-device pci-assign,host=${builtins.getEnv "SNABB_PCI0"},addr=0x15"
        "-device pci-assign,host=${builtins.getEnv "SNABB_PCI1"},addr=0x16"
      ];
    };
  };

  testScript = ''
    startAll;

    # wait for all services to start
    $allinone->waitForUnit("keystone-all.service");
    $allinone->waitForOpenPort(35357);
    $allinone->waitForOpenPort(5000);
    $allinone->waitForUnit("glance-api.service");
    $allinone->waitForOpenPort(9191);
    $allinone->waitForOpenPort(9292);
    $allinone->waitForUnit("neutron-server.service");
    $allinone->waitForUnit("nova-api.service");
    $allinone->waitForOpenPort(8774);
    $allinone->waitForUnit("nova-compute.service");
    $allinone->waitForUnit("nova-conductor.service");

    # set up openstack resources
    $allinone->execute('/root/bootstrap.sh');

    subtest "VM with NIC", sub {
      $allinone->succeed('/root/tests/zone_test_01.sh');
    };

    subtest "VM with 2xNIC (low bandwidth)", sub {
      $allinone->succeed('/root/tests/zone_test_02.sh');
    };

    subtest "VM with 2xNIC (high bandwidth)", sub {
      $allinone->succeed('/root/tests/zone_test_03.sh');
    };

    subtest "2xVM on same physical port", sub {
      $allinone->succeed('/root/tests/zone_test_04.sh');
    };

   subtest "2xVM on different physical port", sub {
     $allinone->succeed('/root/tests/zone_test_05.sh');
   };

    subtest "2xVM with security group restrictions", sub {
      $allinone->succeed('/root/tests/zone_test_06.sh');
    };

    subtest "2xVM bandwidth restriction", sub {
      $allinone->succeed('/root/tests/zone_test_07.sh');
    };

    subtest "VM with L2TPv3", sub {
      $allinone->succeed('/root/tests/zone_test_08.sh');
    };

    subtest "Multiple VMs", sub {
      $allinone->succeed('/root/tests/zone_test_09.sh');
    };

    subtest "VM with NIC, invalid zone", sub {
      $allinone->succeed('/root/tests/zone_test_10.sh');
    };

    subtest "2xVM on different physical port, restart neutron", sub {
      $allinone->succeed('/root/tests/zone_test_11.sh');
    };

    subtest "2xVM on different physical port, restart nova", sub {
      $allinone->succeed('/root/tests/zone_test_12.sh');
    };

    subtest "2xVM on different physical port, restart snabb services", sub {
      $allinone->succeed('/root/tests/zone_test_13.sh');
    };

    subtest "L2TPv3 between 2 VMs", sub {
      $allinone->succeed('/root/tests/zone_test_14.sh');
    };

    subtest "L2TPv3 between 2 VMs add remove tunnel", sub {
      $allinone->succeed('/root/tests/zone_test_15.sh');
    };

    subtest "2xVM with security group restrictions", sub {
      $allinone->succeed('/root/tests/zone_test_16.sh');
    };

    subtest "2xVM on same physical port IPv4", sub {
      $allinone->succeed('/root/tests/zone_test_17.sh');
    };

    subtest "2xVM with security group restrictions and stateless filtering", sub {
      $allinone->succeed('/root/tests/zone_test_18.sh');
    };
  '';
}
