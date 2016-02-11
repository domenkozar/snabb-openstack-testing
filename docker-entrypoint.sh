#!/bin/sh

# we rebuild the tests with environment variables about pci devices
nix-build tests.nix -I /snabb/ -A driver --option build-use-substitutes false

# we run tests as separate step as qemu needs to be run to do pci assignment
tests='eval $ENV{testScript}; die $@ if $@;' ./result/bin/nixos-test-driver

