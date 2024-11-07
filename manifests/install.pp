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
      '9': {
        # https://www.redhat.com/en/blog/rhel-9-networking-say-goodbye-ifcfg-files-and-hello-keyfiles
        package { 'NetworkManager-initscripts-updown': }
      }
      default: {}
    }
    if $manage_iproute {
      package { 'iproute': }
    }
  }
}
