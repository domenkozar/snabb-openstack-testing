[Snabb Switch](https://github.com/SnabbCo/snabbswitch) functional testing suite for [OpenStack](https://www.openstack.org/) integration using [NixOS](http://nixos.org/)


# Usage

Preqrequisites:

- You have installed VirtualBox on your machine and it's able to launch a guest VM. (on NixOS use `virtualisation.virtualbox.host.enable = true;`)

Install nixops

    $ nix-env -i nixops

Get the OpenStack NixOS modules

    $ git clone -b nixos/openstack --single-branch https://github.com/domenkozar/nixpkgs.git

Deploy the cluster on VirtualBox

    $ nixops create -d openstack ./openstack.nix ./openstack-vbox.nix
    $ nixops deploy -d openstack -I `pwd`

Inside the virtualbox guest run the bootstrapping script

    $ nixops ssh -d openstack allinone
    $ source ./bootstrap.sh
