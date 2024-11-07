# Changelog

All notable changes to this project will be documented in this file.

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

## Release 1.7.1

**Features**

* Added support for Rocky Linux 9 (workaround)

**Bugfixes**

* Bugfix for `Tried to load unspecified class: Puppet::Util::Execution::ProcessOutput); replacing`

**Known Issues**