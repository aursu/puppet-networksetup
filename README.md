# networksetup

This module is able to contol several aspects of networking configuration for
RedHat based OSes.

#### Table of Contents

1. [Description](#description)
2. [Setup - The basics of getting started with networksetup](#setup)
    * [What networksetup affects](#what-networksetup-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with networksetup](#beginning-with-networksetup)
3. [Usage - Configuration options and additional functionality](#usage)
4. [Limitations - OS compatibility, etc.](#limitations)
5. [Development - Guide for contributing to the module](#development)

## Description

This module is able to contol several aspects of networking configuration for
RedHat based OSes.

It is possible to match IP address to interface MAC address and setup loopback
interface

There is ability to add IP address to existing interface and setup IP address
alias

## Setup

### What networksetup affects **OPTIONAL**

If it's obvious what your module touches, you can skip this section. For example, folks can probably figure out that your mysql_instance module affects their MySQL instances.

If there's more that they should know about, though, this is the place to mention:

* Files, packages, services, or operations that the module will alter, impact, or execute.
* Dependencies that your module automatically installs.
* Warnings or other important notices.

### Setup Requirements **OPTIONAL**

### Beginning with networksetup

The very basic steps needed for a user to get the module up and running. This can include setup steps, if necessary, or it can be an example of the most basic use of the module.

## Usage

Include usage examples for common use cases in the **Usage** section. Show your users how to use your module to solve problems, and be sure to include code examples. Include three to five examples of the most important or common tasks a user can accomplish with your module. Show users how to accomplish more complex tasks that involve different types, classes, and functions working in tandem.

### Netplan (Debian based systems)

`networksetup::netplan` manages a single netplan configuration file. Netplan is
only a front end: it translates its YAML into systemd-networkd (or
NetworkManager) configuration under `/run`, so the class keeps the two steps
apart. `netplan generate` re-renders that backend configuration and validates
the file without touching anything that is running; `netplan apply`
reconfigures the live interfaces. `generate` is ordered before `apply`, so a
malformed configuration fails the agent run before it can be activated.

```puppet
class { 'networksetup::netplan':
  ethernets => {
    'ens3f0' => { 'dhcp4' => false },
    'ens3f1' => { 'dhcp4' => false },
  },
  bonds     => {
    'bond0' => {
      'dhcp4'      => false,
      'interfaces' => ['ens3f0', 'ens3f1'],
      'parameters' => {
        'mode'                 => '802.3ad',
        'lacp-rate'            => 'fast',
        'mii-monitor-interval' => 100,
      },
    },
  },
  vlans     => {
    'eth0' => {
      'id'          => 316,
      'link'        => 'bond0',
      'addresses'   => ['10.0.0.10/26'],
      'nameservers' => { 'addresses' => ['10.0.1.1', '10.0.1.2'] },
      'routes'      => [{ 'to' => 'default', 'via' => '10.0.0.1' }],
    },
  },
}
```

Every property accepted is declared in the `Networksetup::Netplan::*` data
types, so an unsupported or malformed key is rejected when the catalogue is
compiled rather than by the netplan parser on the host. Supported today:

| Section | Properties |
|---|---|
| all devices | `dhcp4`, `dhcp6`, `addresses`, `mtu`, `nameservers` (`addresses`, `search`), `routes` (`to`, `via`, `metric`) |
| `ethernets` | the above only |
| `bonds` | `interfaces`, `parameters` (`mode`, `lacp-rate`, `mii-monitor-interval`) |
| `vlans` | `id`, `link` |
| top level | `version`, `renderer` |

Not yet rendered, and therefore rejected: `match`, `set-name`, `macaddress`,
`bridges`, `tunnels`, `wifis`, `routing-policy`, and the remaining bond and
route properties. Extending the module means adding the key to the relevant
type and to the template.

`netplan try` is deliberately not offered. It requires a terminal - it opens
one on stdin and waits for a confirmation keypress, reverting when the timeout
expires - so under an agent run it can only ever revert. It also refuses to run
at all when a bond or bridge carries custom `parameters`, reporting that
reverting them is unsupported and pointing at `netplan apply` instead.

⚠ `apply` reconfigures the live interfaces. On a host reached over the very
network being reconfigured, set `apply => false` and apply out of band.

## Reference

See [REFERENCE.md](REFERENCE.md) for details.

## Limitations

The ifcfg and NetworkManager based classes - `networksetup::sysconfig`,
`networksetup::loopback`, `networksetup::install`, `networksetup::service` and
the `network_iface` / `network_alias` / `network_route` types - support CentOS 7
and Rocky/RHEL 8+ only.

`networksetup::netplan` is the opposite: it supports Debian based systems only
and refuses to compile elsewhere. Ubuntu 22.04 and 24.04 are declared; the unit
suite exercises 22.04, because the facterdb shipped with the current PDK has no
24.04 fact set.

## Development

Please submit GitHub pull request for review.
Rspec unit tests are required for any introduced changes

## Release Notes/Contributors/Etc. **Optional**

See [CHANGELOG.md](CHANGELOG.md) for details
