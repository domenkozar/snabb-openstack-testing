[Snabb Switch](https://github.com/SnabbCo/snabbswitch) functional testing suite for [OpenStack](https://www.openstack.org/) integration using [NixOS](http://nixos.org/)


# Usage

Preqrequisites:

- You have installed VirtualBox on your machine and it's able to launch a guest VM.
  (on NixOS use `virtualisation.virtualbox.host.enable = true;`)

Install NixOps

    $ nix-env -i nixops

Get the OpenStack NixOS modules

    $ git clone -b nixos/openstack --single-branch https://github.com/domenkozar/nixpkgs.git

Create NixOps deployment

    $ nixops create -d openstack ./openstack.nix ./openstack-vbox.nix

Build the deployment (we have to do it as separate step otherwise VirtualBox/Qemu fight for the driver)

    $ nixops deploy -d openstack -I `pwd` --build-only -j 4

Deploy the cluster on VirtualBox

    $ nixops deploy -d openstack -I `pwd`

Inside the VirtualBox guest run the bootstrapping script (sets up OpenStack resources)

    $ nixops ssh -d openstack allinone
    $ source ./bootstrap.sh
