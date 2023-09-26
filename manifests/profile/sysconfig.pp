# @summary A short summary of the purpose of this class
#
# A description of what this class does
#
# @example
#   include networksetup::profile::sysconfig
class networksetup::profile::sysconfig {
  include networksetup::install
  include networksetup::sysconfig
  include networksetup::service

  Class['networksetup::install']
  -> Class['networksetup::sysconfig']
  ~> Class['networksetup::service']
}
