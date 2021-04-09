Puppet::Type.newtype(:network_addr) do
  @doc = <<-PUPPET
    @summary
      Network address resource
    PUPPET

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, namevar: true) do
    desc 'IP address'

    # validate do |val|
    #   raise Puppet::ParseError, _('ipaddr must be a valid IP address') unless provider.validate_ip(val)
    # end
  end

  newproperty(:device) do
    desc 'Interface name of the device (DEVICE)'

    validate do |val|
      raise Puppet::Error, _("Invalid device name \"#{val}\"") unless val =~ %r{^[-0-9A-Za-z_]*$}
    end
  end

  newproperty(:hwaddr) do
    desc 'Device hardware address from network script (HWADDR)'

    validate do |val|
      raise Puppet::ParseError, _("\"#{val}\" must be a valid MAC address") unless provider.validate_mac(val)
    end

    munge do |val|
      val.upcase.tr('-', ':')
    end
  end

  newproperty(:label) do
    desc 'Address label on device'

    validate do |val|
      return true if val =~ %r{^([-0-9A-Za-z_]+):([0-9A-Za-z_]+)$}
      return true if val =~ %r{^[0-9A-Za-z_]+$}
      raise Puppet::Error, _("Alias name \"#{val}\" is too long") if val.length > 15
      raise Puppet::Error, _("Invalid alias name \"#{val}\"")
    end
  end

  validate do
    hwaddr = self[:hwaddr]

    # setup IP mask depends on IPv6/IPv4 address
    if hwaddr
      self[:device] = provider.get_device_by_hwaddr(hwaddr) unless self[:device]
    end

    if self[:device].nil? || self[:device].empty?
      raise Puppet::Error, _("error: device does not exist for hw address #{hwaddr}") if hwaddr
      raise Puppet::Error, _("error: didn't specify device")
    end

    if self[:label]
      device, label = self[:label].split(':')

      if label
        return true if device == self[:device]
        raise Puppet::Error, _('error: label does not match device')
      end

      self[:label] = [self[:device], self[:label]].join(':')
    end
  end
end
