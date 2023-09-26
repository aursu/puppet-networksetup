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
  ] $ensure = 'running',
  Boolean $enable = true,
) {
  service { 'network':
    ensure => $ensure,
    enable => $enable,
  }
}
