# @summary Install system tools to manage networking
#
# Install system tools to manage networking
#
# @param manage_initscripts
#   Whether to install the package providing the ifcfg network scripts.
#
# @param manage_iproute
#   Whether to install the iproute package, which provides the ip command every
#   ip provider calls.
#
# @param manage_nm
#   Whether to install NetworkManager: the initscripts compatibility package on
#   EL9, NetworkManager itself on EL10 and newer.
#
# @example
#   include networksetup::install
class networksetup::install (
  Boolean $manage_initscripts = $networksetup::globals::manage_initscripts,
  Boolean $manage_iproute = $networksetup::globals::manage_iproute,
  Boolean $manage_nm = $networksetup::globals::manage_nm,
) inherits networksetup::globals {
  if $facts['os']['family'] == 'RedHat' {
    $major = Integer($facts['os']['release']['major'])

    case $major {
      8: {
        if $manage_initscripts {
          package { $networksetup::params::initscripts: }
        }
      }
      9: {
        file { '/etc/sysconfig/network-scripts':
          ensure => directory,
        }

        # https://www.redhat.com/en/blog/rhel-9-networking-say-goodbye-ifcfg-files-and-hello-keyfiles
        if $manage_nm {
          package { 'NetworkManager-initscripts-updown': }
        }
      }
      # A release older than 8 is no longer this module's business, and must
      # not fall into the branch below: EL6 and EL7 are still running in the
      # fleet, and installing NetworkManager on them is not what dropping their
      # support was meant to do.
      Integer[0, 7]: {}
      default: {
        # Rocky/RHEL 10+: pure NetworkManager, no ifcfg files
        # Ensure NetworkManager is installed (should be by default)
        if $manage_nm {
          package { 'NetworkManager':
            ensure => installed,
          }
        }
      }
    }

    if $manage_iproute {
      package { 'iproute': }
    }
  }
}
