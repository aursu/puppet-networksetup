require 'ipaddr'

Puppet::Functions.create_function(:'networksetup::ipv6_compile') do
  dispatch :ipv6_compile do
    param 'String', :ipv6_netprefix
    param 'Stdlib::IP::Address', :ipv4_addr
    optional_param 'Integer', :ipv6_prefixlength
  end

  def validate_ip(ip)
    return nil unless ip
    IPAddr.new(ip)
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    nil
  end

  def host_number(ipv4_addr = nil)
    addr = validate_ip(ipv4_addr)
    addr.to_i.to_s(16).rjust(8, '0') if addr
  end

  # Hex representation of IPv4 in 2 octets divided by colon
  # return String or nil
  def addr_host_number(ipv4_addr = nil)
    host_nr = host_number(ipv4_addr)

    # split hex representation of IPv4 address on 2 parts and join them with ":"
    (host_nr[0, 4] + ':' + host_nr[4, 4]) if host_nr
  end

  def ipv6_compile(ipv6_netprefix, ipv4_addr, ipv6_prefixlength = 64)
    host_nr = addr_host_number(ipv4_addr)

    addr = [ipv6_netprefix, host_nr].join(':')

    return nil unless validate_ip(addr)
    [addr, ipv6_prefixlength].join('/')
  end
end
