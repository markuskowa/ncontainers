{
  description = "The base flake for on-the-fly NixOS containers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    forAllSystems = function:
      nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ] (system: function nixpkgs.legacyPackages.${system});

  in
  {

    lib.eval = import ./eval.nix;

    packages = forAllSystems (pkgs: {

    });

    templates.default = {
      path = ./template;
      description = "Default template with node definitions";
    };
  };
}
