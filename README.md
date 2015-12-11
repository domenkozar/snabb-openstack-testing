[Snabb Switch](https://github.com/SnabbCo/snabbswitch) functional testing suite for [OpenStack](https://www.openstack.org/) integration using [NixOS](http://nixos.org/)


# Running tests

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

    $ nixops deploy -d openstack -I `pwd` --create-only -j 4
    $ sudo modprobe pci-stub
    $ VBoxManage modifyvm "11c0a2c1-8be9-4f50-9505-d8bc9280c3ef" --nestedpaging on
    $ VBoxManage modifyvm "b3f79aa0-3985-43c1-b428-095624c6ea2d" --chipset ich9
    $ VBoxManage modifyvm "b3f79aa0-3985-43c1-b428-095624c6ea2d" --pciattach 84:00.0@84:00.0

Deploy the cluster on VirtualBox

    $ nixops deploy -d openstack -I `pwd`


Inside the VirtualBox guest run the bootstrapping script (sets up OpenStack resources)

    $ nixops ssh -d openstack allinone
    $ source ./bootstrap.sh


# Docker

Tests can be executed inside a docker container. Docker container ships with all software needed for tests execution.

## Build and publish the image

    $ docker build -t domenkozar/snabb-openstack-testing .
    $ docker push domenkozar/snabb-openstack-testing

## Run the tests

    $ docker run --rm -privileged -ti --e SNABB_PCI0="" -e SNABB_PCI1="" domenkozar/snabb-openstack-testing
