require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_alias).provide(:ip, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network alias.'

  commands ip: 'ip'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def config_path
    name = @resource[:name]
    device = @resource[:device]

    dev, devnum = name.split(':', 2)
    devnum = name unless devnum
    dev = device if device

    "/etc/sysconfig/network-scripts/ifcfg-#{dev}:#{devnum}"
  end
end
