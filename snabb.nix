{ config, pkgs, lib, ... }:

# Start with https://github.com/SnabbCo/snabb/tree/master/src/program/snabbnfv/doc

with lib;

let
  snabb-neutron = with pkgs.pythonPackages; buildPythonPackage {
    name = "snabb-neutron-2015-12-09";

    src = pkgs.fetchFromGitHub {
      owner = "SnabbCo";
      repo = "snabb-neutron";
      rev = "a688d15d1f823e55768dac4eccaad8e579570177";
      sha256 = "0r5pxmq1wchhsq2k6c7a5w23k3i7b2cpdj1rywhdpzxwwad36vnb";
    };

    buildInputs = [ pytest ];
    propagatedBuildInputs = [ pkgs.neutron ];

    preCheck = ''
      #py.test -v snabb_neutron/tests/
    '';

  };
  snabb_dump_path = "/var/lib/snabb/sync";
  cfg = config.services.snabb;
in {
  options.services.snabb = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable snabb NFV integration for Neutron.
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
      snabb = pkgs.snabb.overrideDerivation (super: {
        name = "snabb-dev";
        src = pkgs.fetchFromGitHub {
          owner = "domenkozar";
          repo = "snabbswitch";
          rev = "d2ee06562073307fed0a80f1de862c3c31963791";
          sha256 = "06sn9daa2h2isjqnp163lr1x81ih14j5gxjg5x9s4jfxf7p22m78";
        };
        preConfigure = ''
          make clean
        '';
        buildInputs = super.buildInputs ++ [ pkgs.git ];
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
            serviceConfig.ExecStart = "${pkgs.snabb}/bin/snabb snabbnfv traffic -k 30 -l 10 ${portspec.pci} /var/snabbswitch/ports/port${portspec.portid} /var/lib/libvirt/qemu/%%s.socket";
            # https://github.com/SnabbCo/snabb/blob/master/src/program/snabbnfv/doc/installation.md#traffic-restarts
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
        serviceConfig.ExecStart = "${pkgs.snabb}/bin/snabb snabbnfv neutron-sync-master";
      };

      snabb-neutron-sync-agent = {
        description = "Snabb Agent";
        wantedBy = [ "multi-user.target" ];
        environment = {
          NEUTRON_DIR = "/var/snabbswitch/networks";
          NEUTRON2SNABB = "${pkgs.snabb}/bin/snabb snabbnfv neutron2snabb";
          SYNC_PATH = "sync";
          SYNC_HOST = "localhost";
          SNABB_DIR = "/var/snabbswitch/ports" ;
        };
        preStart = ''
          mkdir -p -m 777 /var/snabbswitch/networks
          mkdir -p -m 777 /var/snabbswitch/ports
        '';
        serviceConfig.ExecStart = "${pkgs.snabb}/bin/snabb snabbnfv neutron-sync-agent";
      };
    };
  };
}
