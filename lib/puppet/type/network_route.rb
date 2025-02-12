require 'puppet/parameter/boolean'

Puppet::Type.newtype(:network_route) do
  @doc = <<-PUPPET
    @summary
      Network route
    PUPPET

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, namevar: true) do
    desc "A unique identifier for the network route (e.g., 'default via 66.175.28.1')."
  end

  newproperty(:destination) do
    desc "The destination network (e.g., '192.168.2.0/24')."

    validate do |value|
      return true if value.match?(%r{^default$})
      raise Puppet::ParseError, _('destination must be a valid IP address or network') unless provider.validate_ip(value)
    end
  end

  newproperty(:gateway) do
    desc "The gateway for the route (e.g., '192.168.1.1')."

    validate do |value|
      raise Puppet::ParseError, _('gateway must be a valid IP address') unless provider.validate_ip(value)
    end
  end

  newproperty(:device) do
    desc 'Interface name'

    validate do |value|
      raise Puppet::Error, _("Invalid interface name \"#{value}\"") unless value.match?(%r{^[-0-9A-Za-z_]*$})
    end
  end

  newparam(:lookup_device) do
    desc 'CIDR network (e.g., "10.50.16.0/24") used to auto-detect the interface if device is not specified.'

    validate do |value|
      raise Puppet::ParseError, _('lookup_device must be a valid CIDR network') unless provider.validate_ip(value)
    end
  end

  newparam(:nocreate, boolean: true, parent: Puppet::Parameter::Boolean) do
    desc 'Do not create configuration script if it is not exists'

    defaultto false
  end

  validate do
    unless self[:nocreate]
      unless self[:device] || self[:lookup_device]
        raise Puppet::Error, _("Either device or lookup_device must be specified to save network_route \"#{self[:name]}\" permanently")
      end
    end
  end
end
