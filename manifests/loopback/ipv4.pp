# @summary Add additional IPv4 address to loopback interface
#
# Add additional IPv4 address to loopback interface
#
# @param ipaddr
#   IPv4 address for loopback interface. Could be specified in CIDR notation
#   In such case CIDR prefix would be used if no prefix or netmask provided
#
# @param netmask
#   IP address mask to use
#
# @param prefix
#   IP address prefix to use (CIDR). But netmask has higher priority
#
# @example
#   networksetup::loopback::ipv4 { 'alias1': }
define networksetup::loopback::ipv4 (
  Stdlib::IP::Address::V4 $addr,
  Optional[Stdlib::IP::Address::V4] $netmask = undef,
  Optional[Integer] $prefix  = undef,
) {
  include networksetup::loopback

  $addrinfo = split($addr, '/')

  $addrprefix = $prefix ? {
    Integer => $prefix,
    default => $addrinfo[1],
  }

  network_alias { $name:
    parent_device => 'lo',
    conn_type     => 'Ethernet',
    ipaddr        => $addrinfo[0],
    netmask       => $netmask,
    prefix        => $addrprefix,
    require       => Class['networksetup::loopback'],
  }

  network_addr { $addrinfo[0]:
    device => 'lo',
    label  => $name,
  }
}
