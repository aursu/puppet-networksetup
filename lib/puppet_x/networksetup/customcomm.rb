$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', '..'))
require 'puppet_x/networksetup/customprop'

# Provides common properties and parameters for OpenStack CLI
module CustomComm
  def self.extended(extender)
    extender.newproperty(:conn_type) do
      desc 'Device type from network script (TYPE)'

      newvalues('Ethernet', 'CIPE', 'IPSEC', 'Modem', 'xDSL', 'ISDN',
                'Wireless', 'Token Ring', 'CTC', 'GRE', 'IPIP', 'IPIP6', 'SIT',
                'sit', 'InfiniBand', 'infiniband', 'Bridge', 'Tap',
                # https://github.com/openvswitch/ovs/blob/master/rhel/README.RHEL.rst
                %r{^OVS[A-Za-z]*$})
    end

    extender.newproperty(:ipv6init, parent: PuppetX::NetworkSetup::SwitchProperty) do
      desc 'ipv6init flag from device network script (IPV6INIT)'
    end

    extender.newproperty(:ipaddr, parent: PuppetX::NetworkSetup::IPProperty) do
      desc 'IP address from network script (IPADDR)'
    end

    extender.newproperty(:gateway, parent: PuppetX::NetworkSetup::IPProperty) do
      desc 'Gateway IP address (GATEWAY)'

      validate do |value|
        next if value == 'none'
        super(value)
      end
    end

    extender.newproperty(:ipv6addr, parent: PuppetX::NetworkSetup::IPProperty) do
      desc 'IPv6 address from network script (IPV6ADDR)'

      validate do |value|
        super(value)
        raise Puppet::Error, _('ipv6addr must be an IPv6 address') unless IPAddr.new(value).ipv6?
      end
    end

    extender.newproperty(:ipv6addr_secondaries, array_matching: :all, parent: PuppetX::NetworkSetup::IPProperty) do
      desc 'Additional IPv6 addresses from network script (IPV6ADDR_SECONDARIES)'
    end

    extender.newproperty(:netmask) do
      desc 'Alias network mask from network script (NETMASK)'

      validate do |val|
        raise Puppet::ParseError, _('netmask must be a valid IP address netmask') unless provider.validate_netmask(val)
      end
    end

    extender.newproperty(:prefix) do
      desc 'Alias prefix  network script (NETMASK)'

      validate do |val|
        raise Puppet::ParseError, _('prefix must be an integer between 8 and 32') unless Integer(val) >= 1 && Integer(val) <= 128
      end

      munge do |val|
        Integer(val)
      end
    end
  end
end
