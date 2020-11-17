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
    desc 'New device name'
  end

  newproperty(:type) do
    desc 'Device type'

    newvalues(:veth, :bridge, :vxlan, :bond, :vlan)
  end

  newproperty(:peer_name) do
    desc 'Specifies the virtual pair device name of the VETH tunnel'
  end

  validate do
    if @parameters[:type] == :veth && @parameters[:peer_name] == :absent
      raise Puppet::Error, _('error: peer name property must be specified for VETH tunnel')
    end
  end
end
