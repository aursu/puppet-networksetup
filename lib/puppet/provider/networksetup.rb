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
end
