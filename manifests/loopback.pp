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
  # NETWORK and BROADCAST were ifcfg keys; NetworkManager derives both from the
  # address and stores neither, so declaring them where it is the storage
  # leaves the resource permanently out of sync.
  if $networksetup::globals::nmcli_managed {
    $loopback_conn_type = undef
    $loopback_network   = undef
    $loopback_broadcast = undef
  }
  else {
    $loopback_conn_type = 'Ethernet'
    $loopback_network   = '127.0.0.0'
    $loopback_broadcast = '127.255.255.255'
  }

  network_iface { 'lo':
    conn_type            => $loopback_conn_type,
    ipaddr               => '127.0.0.1',
    netmask              => '255.0.0.0',
    network              => $loopback_network,
    broadcast            => $loopback_broadcast,
    onboot               => true,
    conn_name            => 'loopback',
    ipv6addr_secondaries => $ipv6addr_secondaries,
    ipv6init             => $ipv6init,
  }
}
