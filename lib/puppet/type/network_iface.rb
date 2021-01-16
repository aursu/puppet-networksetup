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

  newproperty(:bootproto) do
    desc 'Boot proto flag from device network script (BOOTPROTO)'

    newvalues('bootp', 'dhcp', 'static', 'none')
  end

  newproperty(:broadcast) do
    desc 'Device broadcast address from network script (BROADCAST)'

    validate do |val|
      raise Puppet::ParseError, _('network_iface :broadcast must be a valid IP address') unless provider.validate_ip(val)
    end
  end

  newproperty(:conn_name) do
    desc 'Device name from network script (NAME)'
  end

  newproperty(:conn_type) do
    desc 'Device type from network script (TYPE)'

    newvalues('Ethernet', 'CIPE', 'IPSEC', 'Modem', 'xDSL', 'ISDN',
              'Wireless', 'Token Ring', 'CTC', 'GRE', 'IPIP', 'IPIP6', 'SIT',
              'sit', 'InfiniBand', 'infiniband', 'Bridge', 'Tap',
              # https://github.com/openvswitch/ovs/blob/master/rhel/README.RHEL.rst
              %r{^OVS[A-Za-z]*$})
  end

  newproperty(:device) do
    desc 'Device ID from network script (DEVICE)'

    defaultto { @resource[:name] }
  end

  newproperty(:hwaddr) do
    desc 'Device hardware address from network script (HWADDR)'

    validate do |val|
      raise Puppet::ParseError, _('network_iface :hwaddr must be a valid MAC address') unless provider.validate_mac(val)
    end

    munge do |val|
      val.upcase.tr('-', ':')
    end
  end

  newproperty(:ipaddr) do
    desc 'Device IP address from network script (IPADDR)'

    validate do |val|
      raise Puppet::ParseError, _('network_iface :ipaddr must be a valid IP address') unless provider.validate_ip(val)
    end
  end

  newproperty(:netmask) do
    desc 'Device network mask from network script (NETMASK)'

    validate do |val|
      raise Puppet::ParseError, _('network_iface :netmask must be a valid IP address') unless provider.validate_ip(val)
    end
  end

  newproperty(:network) do
    desc 'Device network address from network script (NETWORK)'

    validate do |val|
      raise Puppet::ParseError, _('network_iface :network must be a valid IP address') unless provider.validate_ip(val)
    end
  end

  newproperty(:onboot) do
    desc 'onboot flag from device network script (ONBOOT)'

    newvalues('yes', 'no', true, false, :yes, :no, :true, :false)

    munge do |val|
      case val
      when true, :true
        'yes'
      when false, :false
        'no'
      else
        val
      end
    end
  end

  validate do
    if self[:link_kind] == :veth && (self[:peer_name] == :absent || self[:peer_name].nil?)
      raise Puppet::Error, _('error: peer name property must be specified for VETH tunnel')
    end
  end
end
