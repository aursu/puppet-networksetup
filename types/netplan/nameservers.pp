# @summary The `nameservers` mapping of a netplan device
#
# Both members are optional on their own, but netplan ignores an empty mapping,
# so at least one of them should be given for the block to have any effect.
#
# * `addresses` - resolvers offered to the backend for this device
# * `search`    - DNS search domains offered to the backend for this device
type Networksetup::Netplan::Nameservers = Struct[{
    Optional['addresses'] => Array[Stdlib::IP::Address, 1],
    Optional['search']    => Array[Stdlib::Fqdn, 1],
}]
