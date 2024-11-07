# @summary service `network` management
#
# service `network` management
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
