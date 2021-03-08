$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', '..'))
require 'puppet_x/networksetup/customcomm'
require 'puppet_x/networksetup/customprop'

Puppet::Type.newtype(:network_iface) do
  extend CustomComm

  @doc = <<-PUPPET
    @summary
      Network device configuration
    PUPPET

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, namevar: true) do
    desc 'Interface name. To lookup ifcgf script inside /etc/sysconfig/network-scripts'

    validate do |val|
      raise Puppet::Error, _("error: invalid interface name (#{val})") unless val =~ %r{^[-0-9A-Za-z_]*$}
    end
  end

  newproperty(:device) do
    desc 'Interface name of the device (DEVICE)'

    validate do |val|
      raise Puppet::Error, _("error: invalid device name (#{val})") unless val =~ %r{^[-0-9A-Za-z_]*$}
    end
  end

  newproperty(:conn_name) do
    desc 'User friendly name for the connection (NAME)'
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
    desc 'Method used for IPv4 protocol configuration (BOOTPROTO)'

    newvalues('bootp', 'dhcp', 'static', 'none')
  end

  newproperty(:broadcast, parent: PuppetX::NetworkSetup::IPProperty) do
    desc 'Device broadcast address (BROADCAST)'
  end

  newproperty(:hwaddr) do
    desc 'Hardware address of the device in traditional hex-digits-and-colons notation (HWADDR)'

    validate do |val|
      raise Puppet::ParseError, _('hwaddr must be a valid MAC address') unless provider.validate_mac(val)
    end

    munge do |val|
      val.upcase.tr('-', ':')
    end
  end

  newproperty(:network, parent: PuppetX::NetworkSetup::IPProperty) do
    desc 'Device network address from network script (NETWORK)'
  end

  newproperty(:onboot, parent: PuppetX::NetworkSetup::SwitchProperty) do
    desc 'Whether the connection should be autoconnected (ONBOOT)'

    defaultto 'yes'
  end

  newproperty(:defroute, parent: PuppetX::NetworkSetup::SwitchProperty) do
    desc 'Whether to assign default route to connection (DEFROUTE)'
  end

  newproperty(:dns, array_matching: :all, parent: PuppetX::NetworkSetup::IPProperty) do
    desc 'Name server address to be placed in /etc/resolv.conf (DNS{1,2})'
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

    if self[:ipaddr] || (self[:ipv6addr] && self[:ipv6init] == 'yes')
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

    # set device if hwaddr provided
    if self[:hwaddr]
      device = provider.interface_name
      if device
        self[:device] = device
        self[:conn_name] unless self[:conn_name]
      end
    end

    # plugins specifics
    if self[:link_kind] == :veth && (self[:peer_name] == :absent || self[:peer_name].nil?)
      raise Puppet::Error, _('error: peer name property must be specified for VETH tunnel')
    end
  end
end
