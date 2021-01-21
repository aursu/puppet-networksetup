# @summary Setup loopback interface
#
# Setup loopback interface
#
# @example
#   include networksetup::loopback
class networksetup::loopback (
  Array[Stdlib::IP::Address::V6]
        $ipv6addr_secondaries = [],
)
{
  $ipv6init = $ipv6addr_secondaries[0] ? {
    String  => true,
    default => undef,
  }

  network_iface { 'lo':
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
