{ pkgs, lib, config, ... } :

let
  inherit (lib)
  types
  mkOption
  concatStringsSep
  ;

in {
  options = {
    name = mkOption {

    };

    prefix = mkOption {
      type = types.str;
      default = "kv-";
    };

    root = mkOption {
      type = types.str;
      default = "/run/container/${config.prefix}";
    };

    networking = {
      interfaces = mkOption {
        type = types.str;
        description = "Network interface definitions";
        default = "";
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

    commandLine = mkOption { type = types.str; };
  };

  config = {
    commandLine = config.networking.interfaces + " "
      + (concatStringsSep " " (map (f:
        (if f.ro then "--bind-ro " else "--bind ") + f.path
      ) config.files ));
  };
}

# {
#   node1 = {
#     nspawnConfig=
#     nixosConfig
#   };

