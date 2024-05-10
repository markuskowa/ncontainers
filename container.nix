name: { config, lib, ... } :
{
  boot.isContainer = true;
  networking.hostName = lib.mkDefault name;
}
