# @summary Per-release defaults the rest of the module reads
#
# Whether the release still has ifcfg network scripts to manage, and whether
# NetworkManager is what stores the configuration.
#
# @example
#   include networksetup::params
class networksetup::params {
  if $facts['os']['family'] == 'RedHat' {
    $major = Integer($facts['os']['release']['major'])

    case $major {
      8: {
        $initscripts = 'network-scripts'
        $manage_initscripts = true
        $nmcli_managed = false
      }
      9: {
        $manage_initscripts = false
        $nmcli_managed = false
      }
      default: {
        # EL10 and later have no ifcfg support at all. Anything older than 8 is
        # not this module's business any more, but it must not be swept into
        # the NetworkManager branch by a default meaning "everything else" -
        # that would silently change the ifcfg files of a release that still
        # has them.
        $manage_initscripts = false
        $nmcli_managed = $major >= 10
      }
    }
  }
  else {
    $manage_initscripts = false
    $nmcli_managed = false
  }
}
