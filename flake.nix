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
      ] (system: function nixpkgs.legacyPackages.${system} system);

  in
  {

    lib.eval = import ./eval.nix;

    check = self.hydraJobs;

    hydraJobs = forAllSystems (pkgs: system: let
      node1Addr = "192.168.10.1";
      brAddr = "192.168.10.254";
      nodeRunner = self.lib.eval {
        inherit pkgs system;
        inherit (pkgs) lib;
        config = {
          node1 = {
            networking.bridge = "br-kv";
            networking.address = [{address="${node1Addr}"; prefixLength=24;}];
            devices = [ "/dev/kvm" ];
          };
        };
      };
    in  {
        launchSingleNode = (pkgs.nixosTest {
          name =  "Single node test";
          nodes.main = {
            networking.bridges.br-kv.interfaces = [ ];
            networking.interfaces.br-kv.ipv4.addresses = [{address="${brAddr}"; prefixLength=24;}];
          };
          testScript = ''
            start_all()
            main.wait_for_unit("multi-user.target")
            main.succeed("${nodeRunner.node1} start")
            main.wait_until_succeeds("machinectl status kv-node1")
            main.wait_until_succeeds("ping -c 1 ${node1Addr}")
          '';
        });
      });

    templates.default = {
      path = ./template;
      description = "Default template with node definitions";
    };
  };
}
