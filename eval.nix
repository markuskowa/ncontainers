{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, system ? builtins.currentSystem
, config ? {
  node1 = {
    # system = "aarch64-linux";
    networking.bridge = "br-kv";
    files = [ { path  ="/tmp/share"; ro= false; } ];
    networking.address = [{address="192.168.10.1"; prefixLength=24;}];
    networking.ports = [ "2000" ];
  };
  node2 = {
    networking.bridge = "br-kv";
    networking.address = [{address="192.168.10.2"; prefixLength=24;}];
  };
}
} :

let
  inherit (pkgs.lib)
  evalModules
  attrsToList
  mapAttrs
  optionalString
  concatStringsSep
  ;

  systemClosure = node:
    node.nixosConfig.system.build.toplevel;

  # Eval node module
  evalConfig = name: node: evalModules {
    modules = [
      { _module.args = {
         inherit name pkgs system;
         inherit (pkgs) lib;
        };
      }
      (import ./module.nix)
      node
    ];
  };

  # Generate container runner script
  nodeRunners = mapAttrs (name: node:
    let
      system = systemClosure nodeConfig;
      nodeConfig = (evalConfig name node).config;
      rootPath = nodeConfig.root;

      containerScript = pkgs.writeShellScript "container-${name}"
      ''
        # create and clean root dir
        ${pkgs.coreutils}/bin/mkdir -p ${rootPath}

        systemd-nspawn --private-network --private-users=pick --resolv-conf=copy-host --bind-ro /nix/store \
            ${nodeConfig.commandLine} \
            -M "${nodeConfig.prefix + name}" \
            -D ${rootPath} ${system}/init

        ${pkgs.coreutils}/bin/rm -r ${rootPath}
      '';
    in
    pkgs.writeScript "run-${name}" ''
      systemd-run ${optionalString (nodeConfig.host != null) "-H ${nodeConfig.host}"} \
          ${containerScript}
    ''
  ) config;

in {
  all = pkgs.writeShellScript "run-all"
    (concatStringsSep "\n" (map (x: x.value) (attrsToList nodeRunners)));
  } // nodeRunners


