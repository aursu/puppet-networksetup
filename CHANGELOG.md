# Changelog

All notable changes to this project will be documented in this file.

## Release 2.1.3

**Bugfixes**

* `network_iface` on NetworkManager keeps the secondary addresses it does not
  declare. On `lo` the address list has several owners - the interface
  declares `127.0.0.1`, each `network_alias` adds an entry - and a flush wrote
  the list whole from the interface's own address, erasing every alias until
  the aliases put themselves back later in the run. Undeclared secondaries are
  now carried over; declaring them, an empty list included, still writes the
  list whole. A behaviour change on EL10: extra addresses on a profile are no
  longer removed by omission
* `networksetup::loopback` writes its IPv6 list on EL10. `ipv6.addresses` was
  written only with its primary, which the class did not declare, so the
  list never reached the profile. The class now declares `lo`'s own `::1`
  with length 128, and the `nmcli` provider reads and writes
  `ipv6_prefixlength` and reads `ipv6addr_secondaries` as a list - each of
  which alone kept the resource out of sync on every run. EL8 and EL9 are
  unchanged

## Release 2.1.2

**Bugfixes**

* `network_alias` and `network_route` stay on the `ip` provider on EL8 and EL9.
  Their `ip` providers were suitable there but not a default, and with no
  default among the suitable providers Puppet takes the most specific one -
  `nmcli`, which is installed on EL8 and EL9 as well. So an alias kept in an
  `ifcfg` file was looked for in a NetworkManager profile and reported absent;
  a run would have added it to the profile of `lo`. Seen with `--noop` on an
  EL9 node before any run applied it. Both now declare `defaultfor osfamily:
  redhat`, as `network_iface` always did, and a spec checks the choice for
  every type on EL8, EL9 and EL10

## Release 2.1.1

**Bugfixes**

* A release older than 8 is no longer swept into the branch meant for EL10.
  Dropping CentOS 7 in 2.0.0 removed its arm of the release case, and the
  default arm means "everything else" rather than "newer than the ones named" -
  so an EL6 or EL7 node would have been given `nmcli_managed` and had
  NetworkManager installed on it. Both `networksetup::params` and
  `networksetup::install` now compare the release as a number, and anything
  older than 8 gets nothing of its own: whatever is installed there stays,
  Puppet simply stops managing it

  No node in the fleet is affected today - of the 79 EL6 and EL7 nodes running,
  none includes this module - but that is a fact about the fleet and not about
  the module

## Release 2.1.0

**Features**

* `network_alias` can be managed on Rocky/RHEL 10. An alias is not an object in
  NetworkManager - it is one entry of the parent connection's address list - so
  the provider adds and removes single entries rather than writing the property,
  which is what lets several resources share it
* Alias labels survive. NetworkManager has nowhere to store one, so the label is
  applied to the live address with `ip` before the profile is applied, and a
  later run puts it back after a reactivation has stripped it. The alias reports
  its `device` from the live label, which is what makes that run notice
* `network_route` can be managed on Rocky/RHEL 10. A default route is the
  connection gateway and any other route is an entry of its route list; the
  destination decides which
* `network_route` gains a `metric` property, handled by both providers - the
  `ip` one puts it on the live route and into `route-<dev>`, the `nmcli` one
  writes it as the third token of the entry. There was no way to express a
  metric before, on any release
* `network_iface` gains `ipaddr_secondaries`, the IPv4 counterpart of the
  `ipv6addr_secondaries` that ifcfg always had. Where NetworkManager is the
  storage both families are one list, so additional addresses can belong to the
  interface resource instead of to aliases of their own
* A `network_alias` now autorequires the `network_iface` of its parent device:
  the alias is modified through the parent profile, so the ordering is
  correctness rather than tidiness

**Bugfixes**

* `network_iface` no longer takes the first address of a connection for its own.
  On a host whose aliases came from ifcfg files, `127.0.0.1/8` is the *last*
  entry of the loopback connection, and the interface would have rewritten the
  profile on every run
* `networksetup::loopback::ipv4` and `::ipv6` no longer declare `conn_type`
  where NetworkManager is the storage. `TYPE` belongs to the parent connection
  there, and an alias declaring it asks for a change no provider can make
* An `ifcfg` provider refuses `ipaddr_secondaries` rather than writing a line
  initscripts would ignore, as it already does for `bootproto` and `conn_type`

**Known Issues**

* Bridge membership is still not persisted, and never was: `BRIDGE` is written
  to no `ifcfg` file, and setting `bridge` on a non-veth interface has no effect
* Loopback aliases on web nodes are written by the separate `loopbacks` module,
  which still renders `ifcfg` files and calls `ifup`. Until it gains a
  NetworkManager path, those nodes cannot move to EL10 whatever this module can
  do

## Release 2.0.0

**Breaking changes**

* CentOS 7 leaves `operatingsystem_support`. facterdb 4.x carries no centos-7
  factset, so `on_supported_os` had stopped generating examples for it and the
  release had been claimed but not tested for some time
* The `brctl` provider is removed. It was confined to EL6 and EL7, so it could
  not be selected on anything the fleet still runs, and it overrode one method
  to call `brctl addif`
* `bridge-utils` is no longer installed, and `manage_bridge_utils` is gone from
  `networksetup::install` and `networksetup::globals`. A node that has the
  package keeps it; Puppet simply stops managing it

**Features**

* `network_iface` can be managed on Rocky/RHEL 10, where there are no
  `network-scripts`, through a provider that keeps a NetworkManager connection
  profile instead of an `ifcfg` file. It inherits the `ip` provider, so the
  state of an interface is still read and changed with `ip`, and only the
  persistence differs
* A profile is found by connection name, by device, or by **MAC address** - a
  resource can say only "the interface whose MAC is this", which is what a
  hypervisor's control panel tells you, and never name an interface
* A changed profile is applied with `nmcli device reapply`, which does not
  interrupt the running interface. Where NetworkManager cannot reapply a change
  the resource fails and says so; it never reactivates a connection by itself
* `conn_type` accepts NetworkManager's own device types - `loopback`, `dummy`,
  `bond`, `vlan`, `vrf`, `wireguard` and others - none of which `TYPE` in an
  `ifcfg` file could express. A provider that writes `ifcfg` refuses them
* `bootproto` accepts NetworkManager's methods alongside the `ifcfg` ones, and
  treats `none` and `static` as satisfied by `manual`, `dhcp` by `auto`, so a
  manifest written for `ifcfg` stays in sync on a release where NetworkManager
  is the storage. `disabled`, `link-local` and `shared` became expressible
* Added `networksetup::netplan`, which renders a netplan configuration file
  from Puppet data and hands the result to `netplan generate` and
  `netplan apply` when it changes, with the `Networksetup::Netplan::*` data
  types behind it: ethernets, bonds, VLANs, addresses, nameservers and routes
* Added Ubuntu 22.04 and 24.04 to the declared operating systems, for
  `networksetup::netplan` only - every other class remains RedHat

**Bugfixes**

* `network_iface` writes `NM_CONTROLLED=no` again. The default had been dropped
  from the type, which silently changed what every EL8 and EL9 node puts in its
  `ifcfg` files. It now comes from the provider that writes those files, so a
  release storing a NetworkManager profile is not left with a property it can
  never read back and a resource that changes on every run
* `networksetup::loopback` no longer declares `conn_type`, `network`,
  `broadcast` or `conn_name` where NetworkManager is the storage. All four are
  `ifcfg` keys - `TYPE=Ethernet` on a loopback interface was a fiction
  initscripts required - and declaring them made Puppet report a change it
  could not make, or rename a profile it did not create
* `network_iface` no longer raises `NoMethodError` where no provider is
  suitable; it reports what is actually wrong
* Two specs tested nothing: one read a fixture under a name that no longer
  existed, the other checked EL10 against the expectations of a release that
  has `ifcfg` files

**Known Issues**

* Only `network_iface` has a NetworkManager provider. `network_alias` and
  `network_route` still write `ifcfg` files, so on Rocky/RHEL 10 a resource of
  either type fails with `ENOENT` on `/etc/sysconfig/network-scripts`. In
  practice this means `networksetup::loopback::ipv4` and `::ipv6` - loopback
  aliases - do not work there yet
* Bridge membership is not persisted, and never was: `BRIDGE` is written to no
  `ifcfg` file, and setting `bridge` on a non-veth interface has no effect

## Release 1.0.0

**Features**

* Initial release: loopbacks settings

**Bugfixes**

**Known Issues**

## Release 1.1.0

**Features**

* Added netmask validation

**Bugfixes**

* Added compatibility to Ruby < 2.5

**Known Issues**

## Release 1.2.0

**Features**

* Added installation of required tools

**Bugfixes**

**Known Issues**

## Release 1.2.1

**Features**

* Added flags to make software management optional

**Bugfixes**

**Known Issues**

## Release 1.2.2

**Features**

**Bugfixes**

* Added fix for parent_device field

**Known Issues**

## Release 1.2.3

**Features**

**Bugfixes**

* Fix for missed label provider method for network_addr
* Fix for empty addr_lookup output

**Known Issues**

## Release 1.2.4

**Features**

* Added additional properties for network_iface

**Bugfixes**

* Adjusted provider class methods' return values

**Known Issues**

## Release 1.2.5

**Features**

**Bugfixes**

* Added provider brctl with legacy content to allow default :ip provider
  usage on CentOS 8

**Known Issues**

## Release 1.2.6

**Features**

**Bugfixes**

* Added HWADDR field setup into ifcfg script

**Known Issues**

## Release 1.3.0

**Features**

* Introduced ipv6_setup flag to generate IPv6 address based on existing IPv4
* Added IPv6  default gateway
* Introduced ipv6_prefixlength for IPv6 address prefix

**Bugfixes**

*  Corrected prefix and netmask usage (in favor of ipv6_prefixlength)

**Known Issues**

## Release 1.4.0

**Features**

* Added /etc/sysconfig/network configuration management
* Added service `network` Puppet resource to control it

**Bugfixes**

**Known Issues**

## Release 1.4.1

**Features**

**Bugfixes**

* Bugfix: change label on address alias

**Known Issues**

## Release 1.4.2

**Features**

* Added alias name validation on length

**Bugfixes**

**Known Issues**

## Release 1.4.3

**Features**

* Added abilitiees to process MAC address
* Added master/slave parameters for bond slave interfaces

**Bugfixes**

**Known Issues**

## Release 1.4.4

**Features**

* Added abilitiees to remove DNS records from ifcfg file

**Bugfixes**

**Known Issues**

## Release 1.4.5

**Features**

* Added support for settings NM_CONTROLLED and IPV6_DEFROUTE

**Bugfixes**

**Known Issues**

## Release 1.4.6

**Features**

* Added nocreate flag for network_interface in order to not create
  ifcfg script if it does not exist

**Bugfixes**

**Known Issues**

## Release 1.4.7

**Features**

* Added HOSTNAME setting into /etc/sysconfig/network

**Bugfixes**

**Known Issues**

## Release 1.4.8

**Features**

* Added function networksetup::gateway_prediction

**Bugfixes**

**Known Issues**

## Release 1.4.9

**Features**

* Added function networksetup::ipv6_compile

**Bugfixes**

**Known Issues**

## Release 1.4.10

**Features**

* Added function networksetup::local_ips

**Bugfixes**

**Known Issues**

## Release 1.5.0

**Features**

* PDK upgrade

**Bugfixes**

**Known Issues**

## Release 1.5.1

**Features**

**Bugfixes**

* Fix flush method in Puppet::Type::Network_iface::ProviderIp

**Known Issues**

## Release 1.5.2

**Features**

* Added support for UUID setting

**Bugfixes**

**Known Issues**

## Release 1.5.3

**Features**

**Bugfixes**

* Bugfix for network_iface::dns value munge

**Known Issues**

## Release 1.6.0

**Features**

* PDK upgrade to 3.0.0

**Bugfixes**

**Known Issues**

## Release 1.7.2

**Features**

* Added workaround for Rocky Linux 9
* Added `params` and `globals` for flags

**Bugfixes**

* Bugfix for `Tried to load unspecified class: Puppet::Util::Execution::ProcessOutput); replacing`

**Known Issues**

## Release 1.8.2

**Features**

* Added ip route management

**Bugfixes**

* Added bugfix for route_lookup while prefetch
* Missed bridge-utils on EL9+

**Known Issues**