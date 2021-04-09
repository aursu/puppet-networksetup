$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', '..'))
require 'puppet_x/networksetup/customcomm'
require 'puppet_x/networksetup/customprop'

Puppet::Type.newtype(:network_alias) do
  extend CustomComm

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

  newproperty(:device) do
    desc 'Device ID from network script (DEVICE)'

    validate do |val|
      raise Puppet::Error, _("Invalid device name \"#{val}\"") unless val =~ %r{^([-0-9A-Za-z_]+):([0-9A-Za-z_]+)$}
      raise Puppet::Error, _("device name \"#{val}\" is too long") if val.length > 15
    end
  end

  newproperty(:parent_device) do
    desc 'Device ID from network script (DEVICE)'

    validate do |val|
      raise Puppet::Error, _("error: invalid parent device name (#{val})") unless val =~ %r{^[-0-9A-Za-z_]*$}
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
    elsif self[:ipv6addr] && self[:ipv6init] == 'yes'
      addr, prefixlength = self[:ipv6addr].split('/', 2)
      prefixlength ||= 64
      self[:ipv6addr] = if self[:ipv6_prefixlength]
                          addr
                        else
                          [addr, prefixlength].join('/')
                        end
    else
      raise Puppet::Error, _("error: didn't set ipv6init") if self[:ipv6addr]
      raise Puppet::Error, _("error: didn't specify ipaddr and ipv6addr address")
    end
  end
end
