# @summary Install system tools to manage networking
#
# Install system tools to manage networking
#
# @example
#   include networksetup::install
class networksetup::install (
  Boolean $manage_initscripts = true,
  Boolean $manage_bridge_utils = true,
  Boolean $manage_iproute = true,
) {
  if $facts['os']['family'] == 'RedHat' {
    case $facts['os']['release']['major'] {
      '7': {
        if $manage_initscripts {
          package { 'initscripts': }
        }

        if $manage_bridge_utils {
          package { 'bridge-utils': }
        }
      }
      '8': {
        if $manage_initscripts {
          package { 'network-scripts': }
        }
      }
      default: {}
    }
    if $manage_iproute {
      package { 'iproute': }
    }
  }
}
