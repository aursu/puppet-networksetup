# @summary Manage a netplan configuration file
#
# Renders a netplan configuration file from Puppet data and, when the file
# changes, hands the result to netplan.
#
# Netplan itself is only a front end: it translates the YAML below into
# systemd-networkd (or NetworkManager) configuration under `/run`. Two separate
# steps are therefore involved, and the class keeps them separate on purpose:
#
# * `netplan generate` re-renders the backend configuration under `/run`. It
#   validates the file and touches nothing that is currently running, so it is
#   safe to run first and it fails the agent run before anything is activated.
# * `netplan apply` reconfigures the live interfaces.
#
# ⚠ `netplan try` is deliberately **not** offered. It requires a terminal - it
# opens one on stdin and waits for a confirmation keypress, reverting when the
# timeout expires - so under an agent run it can only ever revert. It also
# refuses to run at all when a bond or bridge carries custom `parameters`,
# reporting that reverting them is unsupported and pointing at `netplan apply`.
#
# @param ethernets
#   Physical devices, keyed by interface name.
#
# @param bonds
#   Bonded devices, keyed by bond name. Members are named in `interfaces` and
#   should also be defined under `ethernets`.
#
# @param vlans
#   VLAN devices, keyed by device name. Each needs an `id` and a `link`.
#
# @param version
#   Netplan configuration format version. Only 2 exists.
#
# @param renderer
#   Backend netplan should generate configuration for. Left unset, the netplan
#   default applies, which is `networkd` on a server installation.
#
# @param config
#   Path of the file to manage. Netplan reads every `*.yaml` in `/etc/netplan`
#   in lexical order, so a file managed here can still be overridden by one
#   sorting later - this class manages one file, not the directory.
#
# @param config_mode
#   Mode of the file. Netplan warns about world or group readable
#   configuration, since it may carry wireless credentials, so the default is
#   `0600`.
#
# @param generate
#   Whether to run `netplan generate` when the file changes.
#
# @param apply
#   Whether to run `netplan apply` when the file changes. ⚠ This reconfigures
#   the live interfaces of the host. On a machine reached over the very network
#   being reconfigured, set it to false and apply out of band instead.
#
# @param netplan_command
#   Absolute path of the netplan binary.
#
# @example Bond, VLAN on top of it, and resolvers for the VLAN
#   class { 'networksetup::netplan':
#     ethernets => {
#       'ens3f0' => { 'dhcp4' => false },
#       'ens3f1' => { 'dhcp4' => false },
#     },
#     bonds     => {
#       'bond0' => {
#         'dhcp4'      => false,
#         'interfaces' => ['ens3f0', 'ens3f1'],
#         'parameters' => {
#           'mode'                 => '802.3ad',
#           'lacp-rate'            => 'fast',
#           'mii-monitor-interval' => 100,
#         },
#       },
#     },
#     vlans     => {
#       'eth0' => {
#         'id'          => 316,
#         'link'        => 'bond0',
#         'addresses'   => ['10.0.0.10/26'],
#         'nameservers' => { 'addresses' => ['10.0.1.1', '10.0.1.2'] },
#         'routes'      => [{ 'to' => 'default', 'via' => '10.0.0.1' }],
#       },
#     },
#   }
class networksetup::netplan (
  Hash[String[1], Networksetup::Netplan::Ethernet] $ethernets = {},
  Hash[String[1], Networksetup::Netplan::Bond] $bonds = {},
  Hash[String[1], Networksetup::Netplan::Vlan] $vlans = {},
  Integer[2, 2] $version = 2,
  Optional[Enum['networkd', 'NetworkManager']] $renderer = undef,
  Stdlib::Absolutepath $config = '/etc/netplan/00-installer-config.yaml',
  Stdlib::Filemode $config_mode = '0600',
  Boolean $generate = true,
  Boolean $apply = true,
  Stdlib::Absolutepath $netplan_command = '/usr/sbin/netplan',
) {
  unless $facts['os']['family'] == 'Debian' {
    fail("networksetup::netplan is supported on Debian based systems only, not on ${facts['os']['family']}")
  }

  $devices = {
    'ethernets' => $ethernets,
    'bonds'     => $bonds,
    'vlans'     => $vlans,
  }

  # An otherwise valid netplan file that defines no device at all deconfigures
  # every interface the moment it is applied. Refusing the catalogue is the
  # only safe response to being included without data.
  if $devices.all |$_section, $members| { $members.empty } {
    fail('networksetup::netplan needs at least one of ethernets, bonds or vlans')
  }

  file { $config:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => $config_mode,
    content => epp('networksetup/netplan/config.yaml.epp', {
        'version'  => $version,
        'renderer' => $renderer,
        'devices'  => $devices,
    }),
  }

  if $generate {
    exec { 'netplan generate':
      command     => "${netplan_command} generate",
      path        => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'],
      refreshonly => true,
      logoutput   => on_failure,
      subscribe   => File[$config],
    }
  }

  if $apply {
    exec { 'netplan apply':
      command     => "${netplan_command} apply",
      path        => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'],
      refreshonly => true,
      logoutput   => on_failure,
      subscribe   => File[$config],
    }

    if $generate {
      Exec['netplan generate'] -> Exec['netplan apply']
    }
  }
}
