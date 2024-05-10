{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, system ? builtins.currentSystem
, config
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
        echo "Usage $(basename $0) <start|update|stop|status|shell>"
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
            machinectl shell "${nodeConfig.prefix + name}" \
            ${system}/bin/switch-to-configuration switch
        ;;
        stop)
          ${optionalString (nodeConfig.host != null) "ssh ${nodeConfig.host}"} \
            machinectl shell "${nodeConfig.prefix + name}" \
            /run/current-system/sw/bin/shutdown -h now
        ;;
        status)
          machinectl ${optionalString (nodeConfig.host != null) "-H ${nodeConfig.host}"} \
            status ${nodeConfig.prefix + name}
        ;;
        shell)
          ${optionalString (nodeConfig.host != null) "ssh -t ${nodeConfig.host}"} \
            machinectl shell "${nodeConfig.prefix + name}"
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

