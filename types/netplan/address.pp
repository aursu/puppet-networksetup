# @summary An interface address in CIDR notation
#
# Netplan requires every statically configured interface address to carry a
# prefix length (`10.0.0.10/24`, `2001:db8::a/64`). A bare address without a
# prefix is rejected by the netplan parser, so it is excluded here rather than
# being caught later by `netplan generate`.
type Networksetup::Netplan::Address = Variant[
  Stdlib::IP::Address::V4::CIDR,
  Stdlib::IP::Address::V6::CIDR,
]
