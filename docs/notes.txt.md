## network_iface

### Network interface lookup order (using command `ip link show`)

1. `hwaddr` is top prio to determine the network interface but if device with
  such address does not exist the next priority is behind `device` field
2. `device` has higher priority than interface name. If interface found using
  `hwaddr` has different name, device value would be replaced with such name
3. `name` is Network_iface resource title which by default is device name but
  if no such device found will be used as connection name

### `ifcfg` configuration script lookup order

1. `name` is a high prio. Lookup order:
  1) /etc/sysconfig/network-scripts/ifcfg-<name>
  2) /etc/sysconfig/network-scripts/ifcfg-* with `NAME=<name>`
  3) /etc/sysconfig/network-scripts/ifcfg-* with `DEVICE=<name>`
2. `device` is a second prio. Lookup order:
  1) /etc/sysconfig/network-scripts/ifcfg-<device>
  2) /etc/sysconfig/network-scripts/ifcfg-* with `NAME=<device>`
  3) /etc/sysconfig/network-scripts/ifcfg-* with `DEVICE=<device>`

### Netmask and prefix

If not specified either than both will be set to NETMASK=255.255.255.255 and
PREFIX=32. The existing values from script will be ignored