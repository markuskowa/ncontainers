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
      nodeConfig = (evalConfig name node).config;
      system = systemClosure nodeConfig;
      rootPath = nodeConfig.root;
      machName = nodeConfig.prefix + name;

      # This is the container startup script
      # Note: this is run with systemd-run, all paths need to be defined
      containerScript = pkgs.writeShellScript "container-${machName}"
      ''
        # create and clean root dir
        ${lib.getBin pkgs.coreutils}/bin/mkdir -p ${rootPath}

        ${nodeConfig.extraStartup}

        systemd-nspawn --private-network -U --bind-ro=/nix/store \
            ${nodeConfig.commandLine} \
            --machine "${machName}" \
            --directory "${rootPath}" ${system}/init

        ${optionalString (!nodeConfig.keep) "${lib.getBin pkgs.coreutils}/bin/rm -r ${rootPath}"}
      '';
    in
    pkgs.writeScript "machine-${machName}" ''
      set -eu

      if [ $# != 1 ]; then
        printf "Usage $(basename $0) <start|update|stop|status|shell>\n"
        exit 1
      fi

      check_status () {
        machinectl ${optionalString (nodeConfig.host != null) "-H ${nodeConfig.host}"} \
          status ${machName}
      }

      case "$1" in
        start)
          if check_status > /dev/null; then
            printf "${machName} is already running!\n"
            exit 1
          fi

          ${optionalString (nodeConfig.host != null) "nix-copy-closure --to ${nodeConfig.host} ${containerScript}"}
          systemd-run ${optionalString (nodeConfig.host != null) "-H ${nodeConfig.host}"} \
              ${containerScript}
        ;;
        update)
          ${optionalString (nodeConfig.host != null) "nix-copy-closure --to ${nodeConfig.host} ${containerScript}"}
          ${optionalString (nodeConfig.host != null) "ssh ${nodeConfig.host}"} \
            machinectl shell "${machName}" \
            ${system}/bin/switch-to-configuration switch
        ;;
        stop)
          # Use shutdown command to wait for container shutdown
          ${optionalString (nodeConfig.host != null) "ssh ${nodeConfig.host}"} \
            machinectl shell "${machName}" \
            /run/current-system/sw/bin/shutdown -h now
        ;;
        status)
          check_status
        ;;
        shell)
          ${optionalString (nodeConfig.host != null) "ssh -t ${nodeConfig.host}"} \
            machinectl shell "${machName}"
        ;;
        *)
          printf "Unknown command\n" 1>&2
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

