# @summary Module-wide switches shared by the other classes
#
# The single place where the rest of the module reads what it is allowed to
# manage. It inherits networksetup::params, so the defaults follow the
# operating system release.
#
# @param manage_initscripts
#   Whether the release still has ifcfg network scripts to manage. Defaults to
#   the per-release value from networksetup::params.
#
# @param manage_bridge_utils
#   Whether to install bridge-utils. Only EL7 and EL8 install it; newer
#   releases use the ip providers.
#
# @param manage_iproute
#   Whether to install the iproute package.
#
# @param manage_nm
#   Whether to manage NetworkManager: the package on the releases that need one
#   and the service in networksetup::service.
#
# @param nmcli_managed
#   Whether the release is driven through NetworkManager alone, with no ifcfg
#   files. Defaults to the per-release value from networksetup::params.
#
# @example
#   include networksetup::globals
class networksetup::globals (
  Boolean $manage_initscripts = $networksetup::params::manage_initscripts,
  Boolean $manage_bridge_utils = true,
  Boolean $manage_iproute = true,
  Boolean $manage_nm = true,
  Boolean $nmcli_managed = $networksetup::params::nmcli_managed,
) inherits networksetup::params {}
