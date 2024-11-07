# @summary A short summary of the purpose of this class
#
# A description of what this class does
#
# @example
#   include networksetup::params
class networksetup::params {
  if $facts['os']['family'] == 'RedHat' {
    case $facts['os']['release']['major'] {
      '7':{
        $initscripts = 'initscripts'
        $manage_initscripts = true
      }
      '8': {
        $initscripts = 'network-scripts'
        $manage_initscripts = true
      }
      default: {
        $manage_initscripts = false
      }
    }
  }
  else {
    $manage_initscripts = false
  }
}
