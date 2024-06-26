{ pkgs, lib, config, system, name, ... } :

let
  inherit (lib)
  types
  mkOption
  mkDefault
  mkIf
  concatStrings
  concatStringsSep
  optionalString
  ;

in {
  options = {
    host = mkOption {
      description = "Target host for deployment";
      type = with types; nullOr str;
      default = null;
    };

    system = mkOption {
      type = types.str;
      default = system;
    };

    prefix = mkOption {
      description = "Prefix for container name";
      type = types.str;
      default = "kv-";
    };

    root = mkOption {
      description = "Filesystem root location";
      type = types.str;
      default = "/run/container/${config.prefix}${name}";
    };

    keep = mkOption {
      description = "Keep root filesystem after shutdown";
      type = types.bool;
      default = false;
    };

    extraStartup = mkOption {
      description = "Extra commands to be exectuted on host before startup";
      type = types.lines;
      default = "";
    };

    networking = {
      extraConfig = mkOption {
        type = types.str;
        description = "Network interface definitions (nspawn command line options)";
        default = "";
      };

      address = mkOption {
        description = "IPv4 address for host0 interface (NixOS type networking.interfaces.<>.ipv4.adddresses)";
        default = [];
        type = with types; listOf attrs;
      };

      ports = mkOption {
        type = with types; listOf (oneOf [str port]);
        description = "List of port forwardings (nspawn commanline -p option)";
        default = [];
      };

      bridge = mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Network bridge interface";
      };

      resolvConf = mkOption {
        type = with types; enum [
          "off"
          "copy-host"
          "copy-static"
          "copy-uplink"
          "copy-stub"
          "replace-host"
          "replace-static"
          "replace-uplink"
          "replace-stub"
          "bind-host"
          "bind-static"
          "bind-uplink"
          "bind-stub"
          "delete"
          "auto"
        ];
        description = "systemd-nspawns's --resolv-conf option";
        default = "copy-host";
      };
    };

    files = mkOption {
      description = "Bind mounts";
      default = [];
      type = types.listOf (types.submodule ({...}: {
        options = {
          path = mkOption {
            type = types.str;
          };
          ro = mkOption {
            type = types.bool;
            default = true;
          };
        };
      }));
    };

    nixosConfig = mkOption {
      description = lib.mdDoc ''
        A specification of the desired configuration of this container, as a NixOS module.
      '';
      default = {};
      type = lib.mkOptionType {
        name = "Toplevel NixOS config";
        merge = loc: defs: (import "${toString pkgs.path}/nixos/lib/eval-config.nix" {
          modules =
            let
              extraConfig = { options, ... }: {
                _file = "module at ${__curPos.file}:${toString __curPos.line}";
                config = {
                  # nixpkgs = if options.nixpkgs?hostPlatform && host.options.nixpkgs.hostPlatform.isDefined
                  #           then { inherit (host.config.nixpkgs) hostPlatform; }
                  #           else { inherit (host.config.nixpkgs) localSystem; }
                  # ;
                  nixpkgs = {
                    buildPlatform.system = config.system;
                    hostPlatform.system = config.system;
                  };
                  boot.isContainer = true;
                  networking.hostName = mkDefault name;
                  networking.useDHCP = mkDefault false;
                  networking.interfaces.host0.ipv4.addresses = mkIf (config.networking.address != null) config.networking.address;
                };
              };
            in [ extraConfig ] ++ (map (x: x.value) defs);
          prefix = [ "nixosConfig" ];
          # inherit (config) specialArgs;

          # The system is inherited from the host above.
          # Set it to null, to remove the "legacy" entrypoint's non-hermetic default.
          system = null;
        }).config;
      };
    };

    # internal options
    commandLine = mkOption { type = types.str; default = null; };
  };

  config = {
    commandLine = config.networking.extraConfig
      + " --resolv-conf=${config.networking.resolvConf}"
      # Bind mounts
      + " " + (concatStringsSep " " (map (f:
        (if f.ro then "--bind-ro " else "--bind ") + f.path
      ) config.files ))
      # Port mappings
      + (concatStrings (map (p:
        " -p ${toString p}"
      ) config.networking.ports ))
      # Bridge
      + optionalString (config.networking.bridge != null) " --network-bridge=${config.networking.bridge}"
      ;
  };
}

