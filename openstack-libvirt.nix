{
  allinone = { config, pkgs, ... }:
    {
      deployment.targetEnv = "libvirtd";
      deployment.libvirtd.memorySize = 16 * 1024;
      deployment.libvirtd.baseImageSize = 30;
      # PCI mapping https://docs.fedoraproject.org/en-US/Fedora/13/html/Virtualization_Guide/chap-Virtualization-PCI_passthrough.html
      deployment.libvirtd.extraDevicesXML = ''
        <hostdev mode='subsystem' type='pci' managed='yes'>
          <driver name='kvm' />
          <rom bar='off'/>
          <source>
            <address type="pci" domain='0x0000' bus='0x3' slot='0x00' function='0x0'/>
          </source>
          <address type="pci" domain='0x0000' bus='0x0' slot='0x15' function='0x0'/>
        </hostdev>
        <hostdev mode='subsystem' type='pci' managed='yes'>
          <driver name='kvm' />
          <rom bar='off'/>
          <source>
            <address type="pci" domain='0x0000' bus='0x3' slot='0x00' function='0x1'/>
          </source>
          <address type="pci" domain='0x0000' bus='0x0' slot='0x16' function='0x0'/>
        </hostdev>
      '';
      deployment.libvirtd.headless = true;
    };
}
