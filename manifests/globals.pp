# @summary A short summary of the purpose of this class
#
# A description of what this class does
#
# @example
#   include networksetup::globals
class networksetup::globals (
  Boolean $manage_initscripts = $networksetup::params::manage_initscripts,
  Boolean $manage_bridge_utils = true,
  Boolean $manage_iproute = true,
  Boolean $manage_nm = true,
) inherits networksetup::params {}
