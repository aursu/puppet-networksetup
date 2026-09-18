# @summary service `network` management
#
# service `network` management
#
# @param nm_ensure
#   Desired state of the NetworkManager service.
#
# @param nm_enable
#   Whether NetworkManager is started at boot.
#
# @param network_ensure
#   Desired state of the legacy network service. Only managed on the releases
#   that still have ifcfg network scripts.
#
# @param network_enable
#   Whether the legacy network service is started at boot.
#
# @example
#   include networksetup::service
class networksetup::service (
  Variant[
    Enum['stopped', 'running'],
    Boolean
  ] $nm_ensure = 'running',
  Boolean $nm_enable = true,
  Variant[
    Enum['stopped', 'running'],
    Boolean
  ] $network_ensure = 'running',
  Boolean $network_enable = true,
) inherits networksetup::globals {
  if $networksetup::globals::manage_initscripts {
    service { 'network':
      ensure => $network_ensure,
      enable => $network_enable,
    }
  }

  if $networksetup::globals::manage_nm {
    service { 'NetworkManager':
      ensure => $nm_ensure,
      enable => $nm_enable,
    }
  }
}
