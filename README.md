[Snabb Switch](https://github.com/SnabbCo/snabbswitch) functional testing suite for [OpenStack](https://www.openstack.org/) integration using [NixOS](http://nixos.org/)


# Running tests (with Docker)

Tests can be executed inside a docker container. Docker container ships with all software needed for tests execution.

Docker runs NixOS tests in QEMU machine with OpenStack installed.

Preqrequisites:

- pass `intel_iommu=on` as kernel parameter on host machine where tests are being ran.
- PCI devices are not assigned (`rmmod ixgbe`)


## Run the tests

    $ docker run --rm --privileged -ti -e SNABB_PCI0="84:00.0" -e SNABB_PCI1="84:00.1" domenkozar/snabb-openstack-testing


# Development

## Build and publish Docker image

    $ docker build -t domenkozar/snabb-openstack-testing .
    $ docker push domenkozar/snabb-openstack-testing


## Debugging tests

Preqrequisites:

- You have installed libvirtd and it's running on your machine
  (on NixOS use `virtualisation.libvirtd.enable = true;`)
- You're in group to access libvirtd resources (on NixOS `libvirtd`)

Install NixOps

    $ nix-env -i nixops

Get the OpenStack NixOS modules

    $ git clone -b nixos/openstack --single-branch https://github.com/domenkozar/nixpkgs.git

Create NixOps deployment

    $ nixops create -d openstack ./openstack.nix ./openstack-libvirt.nix

Deploy the cluster on VirtualBox

    $ nixops deploy -d openstack -I `pwd`

Inside the VirtualBox guest run the bootstrapping script (sets up OpenStack resources)

    $ nixops ssh -d openstack allinone
    $ source /root/bootstrap.sh
