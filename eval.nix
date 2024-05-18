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

      # This is the container startup script
      containerScript = pkgs.writeShellScript "container-${name}"
      ''
        # create and clean root dir
        ${pkgs.coreutils}/bin/mkdir -p ${rootPath}

        ${nodeConfig.extraStartup}

        systemd-nspawn --private-network --private-users=pick --resolv-conf=copy-host --bind-ro /nix/store \
            ${nodeConfig.commandLine} \
            -M "${nodeConfig.prefix + name}" \
            -D ${rootPath} ${system}/init

        ${optionalString (!nodeConfig.keep) "${pkgs.coreutils}/bin/rm -r ${rootPath}"}
      '';
    in
    pkgs.writeScript "machine-${name}" ''

      if [ -z "$1" ]; then
        echo "Usage $(basename $0) <start|update|stop|status>"
        exit 1
      fi

      case "$1" in
        start)
          ${optionalString (nodeConfig.host != null) "nix-copy-closure --to ${nodeConfig.host} ${containerScript}"}
          systemd-run ${optionalString (nodeConfig.host != null) "-H ${nodeConfig.host}"} \
              ${containerScript}
        ;;
        update)
          ${optionalString (nodeConfig.host != null) "nix-copy-closure --to ${nodeConfig.host} ${containerScript}"}
          ${optionalString (nodeConfig.host != null) "ssh ${nodeConfig.host}"} \
            machinectl "${nodeConfig.prefix + name}" shell \
            ${system}/bin/switch-to-configuration switch
        ;;
        stop)
          ${optionalString (nodeConfig.host != null) "ssh ${nodeConfig.host}"} \
            machinectl "${nodeConfig.prefix + name}" shell \
            /run/current-system/sw/bin/shutdown -h now
        ;;
        status)
          machinectl ${optionalString (nodeConfig.host != null) "-H ${nodeConfig.host}"} \
            status ${nodeConfig.prefix + name}
        ;;
        *)
          echo "Unknown command"
          exit 1
        ;;
      esac
    ''
  ) config;

in {
  # Pack all run scripts into one
  default = pkgs.writeShellScript "machine-all"
    (concatStringsSep "\n" (map (x: "${x.value} $1") (attrsToList nodeRunners)));
  } // nodeRunners

