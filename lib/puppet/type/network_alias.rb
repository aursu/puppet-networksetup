Puppet::Type.newtype(:network_alias) do
  @doc = <<-PUPPET
    @summary
      Network alias configuration
    PUPPET

  ensurable do
    defaultvalues
    defaultto :present
  end

  def self.title_patterns
    [
      [
        %r{^([-0-9A-Za-z_]+):([0-9A-Za-z_]+)$},
        [
          [:parent_device],
          [:name],
        ],
      ],
      [
        %r{^([0-9A-Za-z_]+)$},
        [
          [:name],
        ],
      ],
    ]
  end

  newparam(:name, namevar: true) do
    desc 'Alias name.'

    validate do |val|
      raise Puppet::Error, _("error: invalid alias name (#{val})") unless val =~ %r{^[0-9A-Za-z_]*$}
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

  newproperty(:parent_device) do
    desc 'Device ID from network script (DEVICE)'

    validate do |val|
      raise Puppet::Error, _("error: invalid parent device name (#{val})") unless val =~ %r{^[-0-9A-Za-z_]*$}
    end
  end

  newproperty(:device) do
    desc 'Device ID from network script (DEVICE)'

    validate do |val|
      raise Puppet::Error, _("error: invalid device name (#{val})") unless val =~ %r{^([-0-9A-Za-z_]+):([0-9A-Za-z_]+)$}
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

  newproperty(:ipaddr) do
    desc 'Alias IP address from network script (IPADDR)'

    validate do |val|
      raise Puppet::ParseError, _('ipaddr must be a valid IP address') unless provider.validate_ip(val)
    end
  end

  newproperty(:ipv6addr) do
    desc 'Alias IPv6 address from network script (IPV6ADDR)'

    validate do |val|
      raise Puppet::ParseError, _('ipv6addr must be a valid IP address') unless provider.validate_ip(val)
    end
  end

  newproperty(:ipv6addr_secondaries, array_matching: :all) do
    desc 'Alias IPv6 address from network script (IPV6ADDR)'

    validate do |val|
      raise Puppet::ParseError, _('ipv6addr_secondaries must be an array of valid IP addresses') unless provider.validate_ip(val)
    end
  end

  newproperty(:netmask) do
    desc 'Alias network mask from network script (NETMASK)'

    validate do |val|
      raise Puppet::ParseError, _('netmask must be a valid IP address') unless provider.validate_ip(val)
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

  validate do
    if self[:parent_device]
      self[:device] = [self[:parent_device], self[:name]].join(':') unless self[:device]
    elsif self[:device]
      self[:parent_device], _devnum = self[:device].split(':')
    else
      raise Puppet::Error, _("error: didn't specify device")
    end

    # setup IP mask depends on IPv6/IPv4 address
    if self[:ipaddr]
      fullmask = '255.255.255.255'
      maxprefix = 32
      anyaddr = '0.0.0.0'
      _addr, prefix = self[:ipaddr].split('/', 2)
    elsif self[:ipv6init] == 'yes' && self[:ipv6addr]
      fullmask = 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
      maxprefix = 128
      anyaddr = '::'
      _addr, prefix = self[:ipv6addr].split('/', 2)
    else
      raise Puppet::Error, _("error: didn't set ipv6init") if self[:ipv6addr]
      raise Puppet::Error, _("error: didn't specify ipaddr and ipv6addr address")
    end

    if self[:netmask]
      self[:prefix] = IPAddr.new(anyaddr).mask(self[:netmask]).prefix
    elsif self[:prefix] || prefix
      self[:prefix] = prefix unless self[:prefix]
      self[:netmask] = IPAddr.new(fullmask).mask(self[:prefix].to_i).to_s
    else
      self[:netmask] = fullmask
      self[:prefix] = maxprefix
    end
  end
end
