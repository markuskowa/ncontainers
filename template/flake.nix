{
  description = "NixOS containers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-23.11";
    ncontainers = {
      url = "/home/markus/src/ncontainers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ncontainers }: let
    forAllSystems = function:
      nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ] (system: function nixpkgs.legacyPackages.${system} system);

  in
  {
    packages = forAllSystems (pkgs: system:
      ncontainers.lib.eval {
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
        inherit system;
        config = {
          node1 = {};
        };
      }
    );
  };
}
