{
  description = "NixOS ncontainers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-23.11";
    ncontainers = {
      url = "git+https://gitea.home/markus/ncontainers.git";
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
        inherit pkgs system;
        config = {
          node1 = {};
        };
      }
    );
  };
}
