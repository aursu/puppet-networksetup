require 'json'
require 'shellwords'

class Puppet::Provider::NetworkSetup < Puppet::Provider
  initvars

  commands ip: 'ip'

  if command('ip')
    confine true: begin
                    ip('-V')
                  rescue Puppet::ExecutionFailure
                    false
                  else
                    true
                  end
  end

  def self.ip_comm
    command(:ip)
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

  def self.provider_caller(*args)
    provider_command unless @cmd

    cmdline = Shellwords.join(args)

    cmd = [@cmd, cmdline].compact.join(' ')

    cmdout = Puppet::Util::Execution.execute(cmd)
    return nil if cmdout.nil?
    return nil if cmdout.empty?
    return cmdout
  rescue Puppet::ExecutionFailure => detail
    Puppet.debug "Execution of #{@cmd} command failed: #{detail}"
    false
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
