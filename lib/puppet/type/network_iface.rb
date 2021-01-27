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

    validate do |val|
      raise Puppet::Error, _("error: invalid interface name (#{val})") unless val =~ %r{^[-0-9A-Za-z_]*$}
    end
  end

  newproperty(:conn_name) do
    desc 'Device name from network script (NAME)'
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

    validate do |val|
      raise Puppet::Error, _("error: invalid device name (#{val})") unless val =~ %r{^[-0-9A-Za-z_]*$}
    end
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

  newproperty(:ipv6init) do
    desc 'ipv6init flag from device network script (IPV6INIT)'

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

  newproperty(:ipv6addr) do
    desc 'Alias IPv6 address from network script (IPV6ADDR)'

    validate do |val|
      raise Puppet::ParseError, _('ipv6addr must be a valid IP address') unless provider.validate_ip(val)
      raise Puppet::Error, _('ipv6addr must be an IPv6 address') unless IPAddr.new(val).ipv6?
    end
  end

  newproperty(:ipv6addr_secondaries, array_matching: :all) do
    desc 'Alias IPv6 address from network script (IPV6ADDR)'

    validate do |val|
      raise Puppet::ParseError, _('ipv6addr_secondaries must be an array of valid IP addresses') unless provider.validate_ip(val)
    end
  end

  newproperty(:netmask) do
    desc 'Device network mask from network script (NETMASK)'

    validate do |val|
      raise Puppet::ParseError, _('netmask must be a valid IP address netmask') unless provider.validate_netmask(val)
    end
  end

  newproperty(:prefix) do
    desc 'Alias prefix  network script (NETMASK)'

    validate do |val|
      raise Puppet::ParseError, _('prefix must be an integer between 8 and 32') unless Integer(val) >= 1 && Integer(val) <= 128
    end

    munge do |val|
      Integer(val)
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

    defaultto 'yes'

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
    # setup IP mask depends on IPv6/IPv4 address
    if self[:ipaddr]
      fullmask = '255.255.255.255'
      maxprefix = 32
      # anyaddr = '0.0.0.0'
      _addr, prefix = self[:ipaddr].split('/', 2)
    elsif self[:ipv6addr] && self[:ipv6init] == 'yes'
      fullmask = 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
      maxprefix = 128
      # anyaddr = '::'
      _addr, prefix = self[:ipv6addr].split('/', 2)
    end

    if self[:ipaddr] || (self[:ipv6init] && self[:ipv6init] == 'yes')
      if self[:netmask]
        # self[:prefix] = IPAddr.new(anyaddr).mask(self[:netmask]).prefix
        self[:prefix] = provider.netmask_prefix(self[:netmask])
      elsif self[:prefix] || prefix
        self[:prefix] = prefix unless self[:prefix]
        self[:netmask] = IPAddr.new(fullmask).mask(self[:prefix].to_i).to_s
      else
        self[:netmask] = fullmask
        self[:prefix] = maxprefix
      end
    end

    # plugins specifics
    if self[:link_kind] == :veth && (self[:peer_name] == :absent || self[:peer_name].nil?)
      raise Puppet::Error, _('error: peer name property must be specified for VETH tunnel')
    end
  end
end
