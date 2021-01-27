# @summary Install system tools to manage networking
#
# Install system tools to manage networking
#
# @example
#   include networksetup::install
class networksetup::install
{
  if $facts['os']['family'] == 'RedHat' {
    case $facts['os']['release']['major'] {
      '7': {
        package { 'initscripts': }
        package { 'bridge-utils': }
      }
      '8': {
        package { 'network-scripts': }
      }
      default: {}
    }
    package { 'iproute': }
  }
}
