# @summary A device entry of the netplan `vlans` mapping
#
# * `id`   - 802.1Q VLAN tag
# * `link` - the device the VLAN is created on top of; it must be defined under
#            `ethernets` or `bonds`
type Networksetup::Netplan::Vlan = Struct[{
    'id'                    => Integer[0, 4094],
    'link'                  => String[1],
    Optional['dhcp4']       => Boolean,
    Optional['dhcp6']       => Boolean,
    Optional['addresses']   => Array[Networksetup::Netplan::Address, 1],
    Optional['mtu']         => Integer[68],
    Optional['nameservers'] => Networksetup::Netplan::Nameservers,
    Optional['routes']      => Array[Networksetup::Netplan::Route, 1],
}]
