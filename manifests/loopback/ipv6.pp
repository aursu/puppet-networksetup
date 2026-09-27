# @summary Add additional IPv6 address to loopback interface
#
# Add additional IPv6 address to loopback interface
#
# @param addr
#   IPv6 address for loopback interface. Could be specified in CIDR notation
#   In such case CIDR prefix would be used if no prefixlength provided
#
# @param prefixlength
#   IPv6 address prefix length to use. Takes priority over a prefix carried in
#   the addr parameter itself
#
# @param addr_secondaries
#   Additional IPv6 addresses to put on the same alias
#   (IPV6ADDR_SECONDARIES)
#
# @example
#   networksetup::loopback::ipv6 { 'alias6': }
define networksetup::loopback::ipv6 (
  Stdlib::IP::Address::V6 $addr,
  Optional[Integer] $prefixlength = undef,
  Array[Stdlib::IP::Address::V6] $addr_secondaries = [],
) {
  include networksetup::loopback

  # TYPE was a key of the alias ifcfg file. In a NetworkManager profile it
  # belongs to the parent connection, and an alias is one entry of that
  # profile's address list - so declaring it here would be a change no
  # provider can make, reported on every run.
  if $networksetup::globals::nmcli_managed {
    $alias_conn_type = undef
  }
  else {
    $alias_conn_type = 'Ethernet'
  }

  $addrinfo = split($addr, '/')

  $addrprefixlen = $prefixlength ? {
    Integer => $prefixlength,
    default => $addrinfo[1],
  }

  network_alias { $name:
    parent_device        => 'lo',
    conn_type            => $alias_conn_type,
    ipv6init             => true,
    ipv6addr             => $addrinfo[0],
    ipv6_prefixlength    => $addrprefixlen,
    ipv6addr_secondaries => $addr_secondaries,
    require              => Class['networksetup::loopback'],
  }

  network_addr { $addrinfo[0]:
    device => 'lo',
    label  => $name,
  }
}
