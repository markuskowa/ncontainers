{ pkgs ? import <nixpkgs> {}
, config ? {
  node1 = {
    system = "aarch64-linux";
    networking.bridge = "br-kv";
    files = [ { path  ="/home"; } ];
    # nixosConfig = { networking.interfaces.host0.ipv4.addresses = [{address="192.168.10.1"; prefixLength=24;}]; };
    networking.address = [{address="192.168.10.1"; prefixLength=24;}];
    networking.ports = [ "2000" ];
  };
}
} :

let
  inherit (pkgs.lib)
  evalModules
  mapAttrs
  optionalString
  ;

  systemClosure = node:
    node.nixosConfig.system.build.toplevel;

  evalConfig = name: node: evalModules {
    modules = [
      { _module.args = {
         inherit name pkgs;
         inherit (pkgs) lib;
        };
      }
      (import ./module.nix)
      node
    ];
  };

in
  mapAttrs (name: node:
    let
      system = systemClosure nodeConfig;
      nodeConfig = (evalConfig name node).config;
      rootPath = nodeConfig.root;

      containerScript = pkgs.writeShellScript "container-${name}"
      ''
        # create and clean root dir
        ${pkgs.coreutils}/bin/mkdir -p ${system}

        systemd-nspawn --private-network --private-users=pick --resolv-conf=copy-host --bind-ro /nix/store \
            ${nodeConfig.commandLine} \
            -M "${nodeConfig.prefix + name}" \
            -D ${rootPath} ${system}/init

        ${pkgs.coreutils}/bin/rm -r ${system}
      '';
    in
    pkgs.writeScript "run-${name}" ''
      systemd-run ${optionalString (nodeConfig.host != null) "-H ${nodeConfig.host}"} \
          --working-directory=${rootPath} ${containerScript}
    ''
  ) config

