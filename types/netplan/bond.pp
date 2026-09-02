# @summary A device entry of the netplan `bonds` mapping
#
# `interfaces` names the members of the bond. They must themselves be defined,
# normally under `ethernets`, or the backend has nothing to enslave.
type Networksetup::Netplan::Bond = Struct[{
    'interfaces'            => Array[String[1], 1],
    Optional['parameters']  => Networksetup::Netplan::Bond::Parameters,
    Optional['dhcp4']       => Boolean,
    Optional['dhcp6']       => Boolean,
    Optional['addresses']   => Array[Networksetup::Netplan::Address, 1],
    Optional['mtu']         => Integer[68],
    Optional['nameservers'] => Networksetup::Netplan::Nameservers,
    Optional['routes']      => Array[Networksetup::Netplan::Route, 1],
}]
