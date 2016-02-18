{ config, pkgs, lib, ... }:

# Start with https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/doc

with lib;

let
  snabb-neutron = with pkgs.pythonPackages; buildPythonPackage {
    name = "snabb-neutron-2015-12-09";

    src = pkgs.fetchFromGitHub {
      owner = "SnabbCo";
      repo = "snabb-neutron";
      rev = "7a86d8af49218f86de2f532eba80c2c21886ac48";
      sha256 = "0cf7mi32y0i0zwkyv1sf7a1lkp7g7rn7crlg2yl4h8z5iscayapk";
    };

    buildInputs = [ pytest ];
    propagatedBuildInputs = [ pkgs.neutron ];

    preCheck = ''
      py.test -v snabb_neutron/tests/
    '';

  };
  snabb_dump_path = "/var/lib/snabb/sync";
  cfg = config.services.snabbswitch;
in {
  options.services.snabbswitch = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable snabbswitch NFV integration for Neutron.
        '';
      };
      ports = mkOption {
        type = types.listOf (types.attrsOf types.str);
        default = [];
        description = ''
          Ports configuration for Snabb.
        '';
        example = ''
          ports = [
            {
              pci = "0000:00:15.0";
              node = "1";
              cpu = "14";
              portid = "0";
            }
            {
              pci = "0000:00:16.1";
              node = "1";
              cpu = "15";
              portid = "1";
            }
          ];
        '';
      };
  };

  config = mkIf cfg.enable {
    # extend neutron with our plugin
    virtualisation.neutron.extraPackages = [ snabb-neutron ];

    # snabb required patch for qemu
    nixpkgs.config.packageOverrides = pkgs:
    {
      qemu = pkgs.qemu.overrideDerivation (super: {
        patches = super.patches ++ [ (pkgs.fetchurl {
          url = "https://github.com/SnabbCo/qemu/commit/f393aea2301734647fdf470724433f44702e3fb9.patch";
          sha256 = "0hpnfdk96rrdaaf6qr4m4pgv40dw7r53mg95f22axj7nsyr8d72x";
        })];
      });
    };


    # one traffic instance per 10G port
    systemd.services = let
      mkService = portspec:
        {
          name = "snabb-nfv-traffic-${portspec.portid}";
          value = {
            description = "";
            after = [ "snabb-neutron-sync-master.service" ];
            wantedBy = [ "multi-user.target" ];
            # TODO: taskset/numa
            serviceConfig.ExecStart = "${pkgs.snabbswitch}/bin/snabb snabbnfv traffic -k 30 -l 10 ${portspec.pci} /var/snabbswitch/ports/port${portspec.portid} /var/lib/libvirt/qemu/%%s.socket";
            # https://github.com/SnabbCo/snabbswitch/blob/master/src/program/snabbnfv/doc/installation.md#traffic-restarts
            serviceConfig.Restart = "on-failure";
          };
        };
    in builtins.listToAttrs (map mkService cfg.ports) //
    {
      snabb-neutron-sync-master = {
        description = "Snabb ";
        after = [ "mysql.service" "neutron-server.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.mysql ];
        environment = {
          DB_USER = "neutron";
          DB_PASSWORD = "neutron";  # TODO: CHANGEME!
          DB_NEUTRON = "neutron";
          DB_DUMP_PATH = snabb_dump_path;
        };
        preStart = ''
          mkdir -p -m 777 ${snabb_dump_path}
          mysql -u root -N -e "GRANT FILE ON *.* TO 'neutron'@'localhost';"
        '';
        serviceConfig.ExecStart = "${pkgs.snabbswitch}/bin/snabb snabbnfv neutron-sync-master";
      };

      snabb-neutron-sync-agent = {
        description = "Snabb Agent";
        wantedBy = [ "multi-user.target" ];
        environment = {
          NEUTRON_DIR = "/var/snabbswitch/networks";
          NEUTRON2SNABB = "${pkgs.snabbswitch}/bin/snabb snabbnfv neutron2snabb";
          SYNC_PATH = "sync";
          SYNC_HOST = "localhost";
          SNABB_DIR = "/var/snabbswitch/ports" ;
        };
        preStart = ''
          mkdir -p -m 777 /var/snabbswitch/networks
          mkdir -p -m 777 /var/snabbswitch/ports
        '';
        serviceConfig.ExecStart = "${pkgs.snabbswitch}/bin/snabb snabbnfv neutron-sync-agent";
      };
    };
  };
}
