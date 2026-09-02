# @summary A single entry of a netplan device `routes` list
#
# * `to`     - destination, either the literal `default` or a network/host
#              address. Netplan also accepts `0.0.0.0/0`, which is equivalent.
# * `via`    - gateway address the destination is reached through
# * `metric` - route priority; lower wins when several routes match
type Networksetup::Netplan::Route = Struct[{
    'to'               => Variant[Enum['default'], Stdlib::IP::Address],
    Optional['via']    => Stdlib::IP::Address,
    Optional['metric'] => Integer[0],
}]
