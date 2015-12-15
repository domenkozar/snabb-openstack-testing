#!/bin/sh
nix-build tests.nix -I /snabb/ -A driver
tests='eval $ENV{testScript}; die $@ if $@;' ./result/bin/nixos-test-driver

