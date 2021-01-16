require 'json'
require 'shellwords'
require 'ipaddr'

#
class Puppet::Provider::NetworkSetup < Puppet::Provider
  initvars

  commands ip: 'ip'
  commands brctl: 'brctl'

  confine true: begin
                  ip('-V')
                rescue Puppet::ExecutionFailure, Puppet::MissingCommand
                  false
                else
                  true
                end

  def self.ip_comm
    command(:ip)
  end

  def self.brctl_comm
    command(:brctl)
  end

  def self.provider_command(bin = nil)
    cmd = nil
    cmd = Puppet::Util.which(bin) if bin
    @cmd = if cmd
             cmd
           else
             ip_comm
           end
    @cmd
  end

  def self.system_command(bin)
    Puppet::Util.which(bin)
  end

  def self.system_caller(bin, *args)
    cmd = system_command(bin)

    cmdargs = Shellwords.join(args)
    cmdline = [cmd, cmdargs].compact.join(' ') if cmd

    cmdout = Puppet::Util::Execution.execute(cmdline) if cmdline
    return nil if cmdout.nil?
    return nil if cmdout.empty?
    return cmdout
  rescue Puppet::ExecutionFailure => detail
    Puppet.debug "Execution of $(#{cmdline}) command failed: #{detail}"
    false
  end

  def self.provider_caller(*args)
    system_caller(provider_command, *args)
  end

  def self.brctl_caller(*args)
    system_caller(brctl_comm, *args)
  end

  def self.validate_ip(ip)
    return nil unless ip
    IPAddr.new(ip)
  rescue ArgumentError
    nil
  end

  def self.validate_mac(mac)
    return nil unless mac
    %r{^([a-f0-9]{2}[:-]){5}[a-f0-9]{2}$} =~ mac.downcase
  end

  def validate_ip(ip)
    self.class.validate_ip(ip)
  end

  def validate_mac(mac)
    self.class.validate_mac(mac)
  end

  def self.parse_config(ifcfg)
    desc = {}

    map = {
      'BOOTPROTO' => 'bootproto',
      'BROADCAST' => 'broadcast',
      'DEVICE'    => 'device',
      'HWADDR'    => 'hwaddr',
      'IPADDR'    => 'ipaddr',
      'NAME'      => 'conn_name',
      'NETMASK'   => 'netmask',
      'NETWORK'   => 'network',
      'ONBOOT'    => 'onboot',
      'TYPE'      => 'conn_type',
    }

    if ifcfg && File.exist?(ifcfg)
      data = File.read(ifcfg)
      data.each_line do |line|
        p, v = line.split('=', 2)
        k = map[p]
        desc[k] = v.sub(%r{^['"]}, '').sub(%r{['"]$}, '') if k
      end
    end

    desc
  end

  def self.get_config_all
    Dir.glob('/etc/sysconfig/network-scripts/ifcfg-*').reject do |config|
      config =~ %r{(~|\.(bak|old|orig|rpmnew|rpmorig|rpmsave))$}
    end
  end

  def self.get_config_by_name(name)
    get_config_all.each do |config|
      desc = parse_config(config)
      return config if desc['conn_name'].casecmp(name)
    end
    ''
  end

  def self.get_config_by_hwaddr(addr)
    get_config_all.each do |config|
      desc = parse_config(config)
      return config if desc['hwaddr'].casecmp(addr)
    end
    ''
  end

  def self.get_config_by_device(device)
    get_config_all.each do |config|
      desc = parse_config(config)
      return config if desc['device'] == device
    end
    ''
  end

  def self.mk_resource_methods
    [:bootproto,
     :broadcast,
     :conn_name,
     :conn_type,
     :device,
     :hwaddr,
     :ipaddr,
     :netmask,
     :network,
     :onboot,
    ].each do |attr|
      define_method(attr) do
        ifcfg_data[attr.to_s]
      end

      define_method(attr.to_s + "=") do |val|
        @property_flush[attr] = val
      end
    end
  end
end
