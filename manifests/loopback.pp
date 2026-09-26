# @summary Setup loopback interface
#
# Setup loopback interface
#
# @param ipv6addr_secondaries
#   Additional IPv6 addresses to put on the loopback interface
#   (IPV6ADDR_SECONDARIES). A non-empty list also turns IPv6 on for it.
#
# @example
#   include networksetup::loopback
class networksetup::loopback (
  Array[Stdlib::IP::Address::V6] $ipv6addr_secondaries = [],
) inherits networksetup::globals {
  $ipv6init = $ipv6addr_secondaries[0] ? {
    String  => true,
    default => undef,
  }

  # TYPE=Ethernet was what initscripts wanted for a loopback interface, which
  # has no Ethernet about it. NetworkManager has a real type for it, and it
  # cannot be changed after the profile exists - so where the storage is
  # NetworkManager the fiction is simply not declared.
  if $networksetup::globals::nmcli_managed {
    $loopback_conn_type = undef
  }
  else {
    $loopback_conn_type = 'Ethernet'
  }

  network_iface { 'lo':
    conn_type            => $loopback_conn_type,
    ipaddr               => '127.0.0.1',
    netmask              => '255.0.0.0',
    network              => '127.0.0.0',
    broadcast            => '127.255.255.255',
    onboot               => true,
    conn_name            => 'loopback',
    ipv6addr_secondaries => $ipv6addr_secondaries,
    ipv6init             => $ipv6init,
  }
}
