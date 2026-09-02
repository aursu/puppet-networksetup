# @summary A physical device entry of the netplan `ethernets` mapping
#
# Only the properties the module renders are accepted - an unsupported key is
# rejected at catalogue compilation instead of producing a netplan file the
# backend later refuses.
type Networksetup::Netplan::Ethernet = Struct[{
    Optional['dhcp4']       => Boolean,
    Optional['dhcp6']       => Boolean,
    Optional['addresses']   => Array[Networksetup::Netplan::Address, 1],
    Optional['mtu']         => Integer[68],
    Optional['nameservers'] => Networksetup::Netplan::Nameservers,
    Optional['routes']      => Array[Networksetup::Netplan::Route, 1],
}]
