# @summary Add additional IPv6 address to loopback interface
#
# Add additional IPv6 address to loopback interface
#
# @param ipaddr
#   IPv6 address for loopback interface. Could be specified in CIDR notation
#   In such case CIDR prefix would be used if no prefix or netmask provided
#
# @param prefix
#   IP address prefix to use (CIDR). But netmask has higher priority
#
# @example
#   networksetup::loopback::ipv6 { 'alias6': }
define networksetup::loopback::ipv6 (
  Stdlib::IP::Address::V6
          $addr,
  Optional[Integer]
          $prefix  = undef,
  Array[Stdlib::IP::Address::V6]
          $addr_secondaries = [],
)
{
  include networksetup::loopback

  $addrinfo = split($addr, '/')

  $addrprefix = $prefix ? {
    Integer => $prefix,
    default => $addrinfo[1],
  }

  network_alias { $name:
    parent_device        => 'lo',
    conn_type            => 'Ethernet',
    ipv6init             => true,
    ipv6addr             => $addrinfo[0],
    prefix               => $addrprefix,
    ipv6addr_secondaries => $addr_secondaries,
    require              => Class['networksetup::loopback'],
  }

  network_addr { $addrinfo[0]:
    device => 'lo',
    label  => $name,
  }
}
