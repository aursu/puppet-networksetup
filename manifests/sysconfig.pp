# @summary Setup networking settings into /etc/sysconfig/network
#
# The /etc/sysconfig/network file specifies additional information that is
# valid to all network interfaces on the system
#
# @param nozeroconf
#   Set this to true to not set a route for dynamic link-local addresses.
#
# @param ipv6_autoconf
#   Sets the default for device-based autoconfiguration. If enabled, an IPv6
#   address will be requested using Neighbor Discovery (ND) from a router
#   running the radvd daemon.
#
# @param ipv6_defaultgw
#   Add a default route through specified gateway. An interface can be
#   specified: required for link-local addresses
#   Examples:
#     IPV6_DEFAULTGW="3ffe:ffff:1234:5678::1"
#       Add default route through 3ffe:ffff:1234:5678::1
#     IPV6_DEFAULTGW="3ffe:ffff:1234:5678::1%eth0"
#       Add default route through 3ffe:ffff:1234:5678::1 and device eth0
#     IPV6_DEFAULTGW="fe80::1%eth0"
#       Add default route through fe80::1 and device eth0
#
# @param hostname
#   Set HOSTNAME variable inside system configuration file /etc/sysconfig/network
#
# @param puppet_propagate
#   Propagate variables inside /etc/sysconfig/network from Puppet facts
#   Parameter hostname has higher priority
#
# @example
#   include networksetup::sysconfig
class networksetup::sysconfig (
  Boolean $nozeroconf = true,
  Boolean $ipv6_autoconf = false,
  Optional[String] $ipv6_defaultgw = undef,
  Optional[Stdlib::Fqdn] $hostname = undef,
  Boolean $puppet_propagate = false,
) {
  $networking = true
  $network_hostname = $hostname

  if $ipv6_defaultgw {
    $ipv6_defaultgw_info = split($ipv6_defaultgw, '%')
    $gw_addr = $ipv6_defaultgw_info[0]

    if $gw_addr !~ Stdlib::IP::Address::V6 {
      fail("ipv6_defaultgw must be a valid IPv6 address, not \"${gw_addr}\"")
    }
  }

  if $puppet_propagate {
    if $::facts['networking']['fqdn'] in ['localhost', 'localhost.localdomain'] {
      $networking_fqdn = undef
    }
    else {
      $networking_fqdn = $::facts['networking']['fqdn']
    }
  }

  file { '/etc/sysconfig/network':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => template('networksetup/network.erb'),
  }
}
