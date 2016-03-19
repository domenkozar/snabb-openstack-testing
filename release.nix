{ nixpkgs ? (import <nixpkgs> {})
, lib ? (import <nixpkgs/lib>)
, supportedSystems ? [ "x86_64-linux" ]
, pci0
, pci1
}:

{
  tests = lib.hydraJob (import ./tests.nix { system = "x86_64-linux"; inherit pci0 pci1; });
}
