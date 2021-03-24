$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', '..'))
require 'puppet_x/networksetup/customcomm'
require 'puppet_x/networksetup/customprop'

require 'puppet/parameter/boolean'

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

  newparam(:ipv6_setup, boolean: true, parent: Puppet::Parameter::Boolean) do
    desc 'Setup IPv6 address based on ipv6_netprefix and host number'

    defaultto false
  end

  newparam(:ipv6_netprefix) do
    desc 'First 6 octects of IPv6 address to combine with host number'
  end

  # Hex representation of IPv4 in 2 octets divided by colon
  # return String or nil
  def addr_host_number(addr = nil)
    host_number = provider.host_number(addr)

    # split hex representation of IPv4 address on 2 parts and join them with ":"
    (host_number[0, 4] + ':' + host_number[4, 4]) if host_number
  end

  validate do
    if self[:ipv6init] == 'yes'
      if self[:ipv6addr]
        addr, prefixlength = self[:ipv6addr].split('/', 2)
        prefixlength ||= 64
        self[:ipv6addr] = if self[:ipv6_prefixlength]
                            addr
                          else
                            [addr, prefixlength].join('/')
                          end
      elsif self[:ipv6_setup]
        # 6-octet network prefix should be provided to generate IPv6 based on IPv4 address
        unless self[:ipv6_netprefix]
          raise Puppet::Error,
                _('error: ipv6_netprefix parameter must be specified when ipv6_setup is true')
        end

        host_number = if self[:ipaddr]
                        addr_host_number(self[:ipaddr])
                      else
                        addr_host_number(provider.ipaddr)
                      end

        raise Puppet::Error, _(<<-EOT) unless host_number
          error: IPADDR must be available in ifcfg script or specified through ipaddr
          property in order to combine IPv6 address
        EOT

        # validate
        addr = [self[:ipv6_netprefix], host_number].join(':')

        unless provider.validate_ip(addr)
          raise Puppet::Error,
                _('error: ipv6_netprefix must be a valid IPv6 address when ending with host number')
        end

        # default IPv6 prefix length is 64
        prefixlength = self[:ipv6_prefixlength] || 64

        self[:ipv6addr] = [addr, prefixlength].join('/')
      end
    end

    # setup IP mask depends on IPv6/IPv4 address
    if self[:ipaddr]
      fullmask = '255.255.255.255'
      maxprefix = 32
      # anyaddr = '0.0.0.0'
      _addr, prefix = self[:ipaddr].split('/', 2)

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
