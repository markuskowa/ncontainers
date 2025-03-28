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
      default = pkgs.system;
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
        description = "Network interface definitions";
        default = "";
      };

      address = mkOption {
        description = "IPv4 address for host0 interface";
        default = [];
        type = with types; listOf attrs;
      };

      ports = mkOption {
        type = with types; listOf (oneOf [str port]);
        description = "List of port forwardings";
        default = [];
      };

      bridge = mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Network bridge interface";
      };
    };

    devices = mkOption {
      type = with types; listOf str;
      default = [];
      example = "[ "/dev/kvm" ]";
      description = "Allow container access to devices";
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
                    # inherit pkgs;
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
    commandLine = config.networking.extraConfig + " "
      + (concatStringsSep " " (map (f:
        (if f.ro then "--bind-ro " else "--bind ") + f.path
      ) config.files ))
      + (concatStrings (map (p:
        " -p ${toString p}"
      ) config.networking.ports ))
      + optionalString (config.networking.bridge != null) " --network-bridge=${config.networking.bridge}"
      + (concatStringsSep " " (map (dev:
         " --bind=${dev} \"--property=DeviceAllow=${dev} rw\""
        ) config.devices))
      ;
  };
}

