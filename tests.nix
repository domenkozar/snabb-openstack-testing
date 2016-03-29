{ system ? builtins.currentSystem
, pci1 ? builtins.getEnv "SNABB_PCI1"
, pci0 ? builtins.getEnv "SNABB_PCI0"
}:

with import <nixpkgs/nixos/lib/testing.nix> {
  inherit system;
  config = {
    packageOverrides = pkgs: {
      qemu_kvm = pkgs.qemu_kvm.overrideDerivation (super: {
        # let's make sure qemu is called as sudo to have permissions for pci-assign
        # this requires sudo-in-builds.nix to be deployed on the server running these tests
        postFixup = ''
          for f in $out/bin/*; do
            f_hidden="$(dirname "$f")/.$(basename "$f")"-nonsudo
            mv $f $f_hidden
            makeWrapper "/var/setuid-wrappers/sudo $f_hidden" $f --argv0 '"$0"' "$@"
          done
        '';
      });
    };
  };
};


let
  lib = import <nixpkgs/lib>;
  qemuFlags = lib.optionalString (pci0 != "") ''
    -device pci-assign,host=${pci0},addr=0x15 -device pci-assign,host=${pci1},addr=0x16 -cpu host
  '';
  config = (import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit system;
    modules = [
      (import ./openstack.nix).allinone
      {
        fileSystems."/".device = "/dev/disk/by-label/nixos";
        boot.loader.grub.device = "/dev/sda";
        networking.hostName = "allinone";
      }
      <nixpkgs/nixos/modules/testing/test-instrumentation.nix>
      <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
    ];
  }).config;
  img = import <nixpkgs/nixos/lib/make-disk-image.nix> {
    inherit lib config;
    pkgs = import <nixpkgs> {};
    partitioned = true;
    diskSize = 80 * 1024;
  };
in lib.overrideDerivation (makeTest {
  name = "snabb-openstack-testing";

  testScript = ''
    # boot qemu with qcow2 image
    my $imageDir = ($ENV{'TMPDIR'} // "/tmp") . "/vm-state-machine";
    mkdir $imageDir, 0700;
    my $diskImage = "$imageDir/machine.qcow2";
    system("qemu-img create -f qcow2 -o backing_file=${img}/nixos.img $diskImage 80G") == 0 or die;

    my $allinone = createMachine({name => "allinone", hda => "$diskImage", qemuFlags => '-m 21504 ${qemuFlags}' });
    $allinone->start;

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
}) (attrs: { __noChroot = true; requiredSystemFeatures = [ "openstack" "kvm" ];})
