require 'ipaddr'

Puppet::Functions.create_function(:'networksetup::local_ips') do
  dispatch :local_ips do
    optional_param 'Optional[Stdlib::IP::Address]', :ipv4_net
  end

  def validate_ip(ip)
    return nil unless ip
    IPAddr.new(ip)
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    nil
  end

  def local_ips(ipv4_net = nil)
    addr = Facter.value(:ipaddress)
    net = validate_ip(ipv4_net)
    
    networking = Facter.value(:networking)
    ips = if networking
            networking['interfaces'].map { |_, iface| iface['bindings'] || [] }.flatten.map { |b| b['address'] }
          else
            [addr]
          end
    if net
      ips.filter { |a| net.include?(a) }
    else
      ips
    end
  end
end