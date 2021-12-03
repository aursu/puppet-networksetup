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
    scope = closure_scope
    networking = scope['facts']['networking']
    addr = networking['ip']

    net = validate_ip(ipv4_net)
    
    ips = networking['interfaces'].map { |_, iface| iface['bindings'] || [] }.flatten.map { |b| b['address'] }

    if net
      ips.filter { |a| net.include?(a) }
    else
      [addr].union(ips)
    end
  end
end