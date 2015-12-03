{
  allinone = { config, pkgs, ... }:
    {
      deployment.targetEnv = "virtualbox";
      deployment.virtualbox.memorySize = 2500; # megabytes
      deployment.virtualbox.headless = true;
    };
}
