Puppet::Type.newtype(:network_iface) do
  @doc = <<-PUPPET
    @summary
      Network device configuration
    PUPPET

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, namevar: true) do
    desc 'Interface name. In use to lookup ifcgf script inside /etc/sysconfig/network-scripts'
  end

  newproperty(:link_kind) do
    desc 'Device link type'

    newvalues(:veth, :bridge, :vxlan, :bond, :vlan)
  end

  newproperty(:peer_name) do
    desc 'Specifies the virtual pair device name of the veth tunnel'
  end

  newproperty(:bridge) do
    desc 'Add interface to the bridge'
  end

  validate do
    if self[:link_kind] == :veth && (self[:peer_name] == :absent || self[:peer_name].nil?)
      raise Puppet::Error, _('error: peer name property must be specified for VETH tunnel')
    end
  end
end
