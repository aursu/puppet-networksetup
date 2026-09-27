# @summary Add additional IPv4 address to loopback interface
#
# Add additional IPv4 address to loopback interface
#
# @param addr
#   IPv4 address for loopback interface. Could be specified in CIDR notation
#   In such case CIDR prefix would be used if no prefix or netmask provided
#
# @param netmask
#   IP address mask to use
#
# @param prefix
#   IP address prefix to use (CIDR). But netmask has higher priority
#
# @param ensure
#   absent takes the address off the loopback interface: out of the lo
#   profile where NetworkManager is the storage, its ifcfg file otherwise.
#
# @example
#   networksetup::loopback::ipv4 { 'alias1': }
define networksetup::loopback::ipv4 (
  Stdlib::IP::Address::V4 $addr,
  Optional[Stdlib::IP::Address::V4] $netmask = undef,
  Optional[Integer] $prefix  = undef,
  Enum['present', 'absent'] $ensure = 'present',
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

  # present is every type's default; it is left undeclared so a present
  # alias compiles exactly as it did before this parameter existed.
  $resource_ensure = $ensure ? {
    'absent' => 'absent',
    default  => undef,
  }

  $addrprefix = $prefix ? {
    Integer => $prefix,
    default => $addrinfo[1],
  }

  network_alias { $name:
    ensure        => $resource_ensure,
    parent_device => 'lo',
    conn_type     => $alias_conn_type,
    ipaddr        => $addrinfo[0],
    netmask       => $netmask,
    prefix        => $addrprefix,
    require       => Class['networksetup::loopback'],
  }

  network_addr { $addrinfo[0]:
    ensure => $resource_ensure,
    device => 'lo',
    label  => $name,
  }
}
