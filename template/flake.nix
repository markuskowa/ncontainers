{
  description = "NixOS containers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-23.11";
    ncontainers = {
      url = "git+https://gitea.home/markus/ncontainers";
      nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ncontainers }: let
    forAllSystems = function:
      nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ] (system: function nixpkgs.legacyPackages.${system});

  in
  {
    packages = forAllSystems (pkgs:
      ncontainers.lib.eval {
        pkgs = nixpkgs.legacyPackages;
        config = {
          node1 = {};
        };
      }
    );
  };
}
