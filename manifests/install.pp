# @summary Install system tools to manage networking
#
# Install system tools to manage networking
#
# @example
#   include networksetup::install
class networksetup::install (
  Boolean $manage_initscripts = $networksetup::globals::manage_initscripts,
  Boolean $manage_bridge_utils = $networksetup::globals::manage_bridge_utils,
  Boolean $manage_iproute = $networksetup::globals::manage_iproute,
  Boolean $manage_nm = $networksetup::globals::manage_nm,
) inherits networksetup::globals {
  if $facts['os']['family'] == 'RedHat' {
    case $facts['os']['release']['major'] {
      '7', '8': {
        if $manage_initscripts {
          package { $networksetup::params::initscripts: }
        }

        if $manage_bridge_utils {
          package { 'bridge-utils': }
        }
      }
      '9': {
        file { '/etc/sysconfig/network-scripts':
          ensure => directory,
        }

        # https://www.redhat.com/en/blog/rhel-9-networking-say-goodbye-ifcfg-files-and-hello-keyfiles
        if $manage_nm {
          package { 'NetworkManager-initscripts-updown': }
        }
      }
      default: {}
    }

    if $manage_iproute {
      package { 'iproute': }
    }
  }
}
