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
  # NAME=loopback is an ifcfg key too. NetworkManager generates its own profile
  # for the loopback interface and calls it lo; declaring a different name
  # makes Puppet rename a profile it did not create, for no effect. The
  # addresses are the module's business here, the name is not.
  if $networksetup::globals::nmcli_managed {
    $loopback_conn_type = undef
    $loopback_network   = undef
    $loopback_broadcast = undef
    $loopback_conn_name = undef
  }
  else {
    $loopback_conn_type = 'Ethernet'
    $loopback_network   = '127.0.0.0'
    $loopback_broadcast = '127.255.255.255'
    $loopback_conn_name = 'loopback'
  }

  # ifcfg kept IPV6ADDR_SECONDARIES on its own; NetworkManager has one
  # ipv6.addresses list, headed by lo's own ::1/128, and writes it only
  # together with that primary. So where it is the storage the primary is
  # declared too - address and length apart, since that is the form the
  # profile is read back in.
  if $networksetup::globals::nmcli_managed and $ipv6init {
    $loopback_ipv6addr          = '::1'
    $loopback_ipv6_prefixlength = 128
  }
  else {
    $loopback_ipv6addr          = undef
    $loopback_ipv6_prefixlength = undef
  }

  network_iface { 'lo':
    conn_type            => $loopback_conn_type,
    ipaddr               => '127.0.0.1',
    netmask              => '255.0.0.0',
    network              => $loopback_network,
    broadcast            => $loopback_broadcast,
    onboot               => true,
    conn_name            => $loopback_conn_name,
    ipv6addr             => $loopback_ipv6addr,
    ipv6_prefixlength    => $loopback_ipv6_prefixlength,
    ipv6addr_secondaries => $ipv6addr_secondaries,
    ipv6init             => $ipv6init,
  }
}
