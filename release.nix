{ nixpkgs ? (import <nixpkgs> {})
, lib ? (import <nixpkgs/lib>)
, supportedSystems ? [ "x86_64-linux" ]
}:

let
in {
  tests = lib.hydraJob (import ./tests.nix { system = "x86_64-linux"; });
}
