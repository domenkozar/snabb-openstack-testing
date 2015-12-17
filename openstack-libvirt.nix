{
  allinone = { config, pkgs, ... }:
    {
      deployment.targetEnv = "libvirtd";
      deployment.libvirtd.memorySize = 2500;
      deployment.libvirtd.baseImageSize = 3;
      deployment.libvirtd.extraDevicesXML = "";
    };
}
