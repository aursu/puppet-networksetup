require 'json'
require 'shellwords'

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

  def empty_or_absent(value)
    return true if value.nil?
    return true if value.is_a?(String) && value.empty?
    return true if value == :absent
    false
  end

  # return array of values except value 'absent'
  # :absent   -> []
  # 'absent'  -> []
  # [:absent] -> []
  # [nil]     -> []
  # 'value'   -> ['value']
  def prop_to_array(prop)
    [prop].flatten.reject { |p| p.to_s == 'absent' }.compact
  end
end
