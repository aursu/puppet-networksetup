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
        $nmcli_managed = false
      }
      '8': {
        $initscripts = 'network-scripts'
        $manage_initscripts = true
        $nmcli_managed = false
      }
      '9': {
        $manage_initscripts = false
        $nmcli_managed = false
      }
      default: {
        # Rocky/RHEL 10+: no ifcfg support, pure NetworkManager
        $manage_initscripts = false
        $nmcli_managed = true
      }
    }
  }
  else {
    $manage_initscripts = false
    $nmcli_managed = false
  }
}
