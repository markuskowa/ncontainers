{ pkgs ? import <nixpkgs> {}
, config ? {
  node1 = {
    nixosConfig = {};
    nspawnConfig = {};
  };
}
} :

let
  inherit (pkgs.lib)
  evalModules
  mapAttrs
  ;

  evalNode = name: node:
    import (pkgs.path + "/nixos/lib/eval-config.nix") {
      modules = [
        node
        (import ./container.nix name)
      ];
    };

  systemClosure = node:
    node.config.system.build.toplevel;

  evalNspawn = nspawn: evalModules {
    modules = [
      { _module.args = {
         inherit pkgs;
         inherit (pkgs) lib;
        };
      }
      (import ./module.nix)
    ];
  };

in
  mapAttrs (name: node:
    let
      evaluatedNode = evalNode name node.nixosConfig;
      system = systemClosure evaluatedNode;
      nspawn = evalNspawn node.nspawnConfig;
      rootPath = nspawn.config.root + name;
    in
    pkgs.writeShellScript "launch-${name}"
    ''
      ${pkgs.coreutils}/bin/mkdir -p ${rootPath}

      ${pkgs.coreutils}/bin/ls -ld ${rootPath}
      systemd-run --working-directory=${rootPath} \
      systemd-nspawn --private-network --private-users=pick --resolv-conf=copy-host --bind-ro /nix \
          ${nspawn.config.commandLine} -M "${nspawn.config.prefix + name}" -D ${rootPath} ${system}/init

    ''
  ) config

