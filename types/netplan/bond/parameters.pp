# @summary The `parameters` mapping of a netplan bond
#
# WARNING: a bond carrying any of these makes the whole configuration
# non-revertable for `netplan try`, which then refuses to run at all. See the
# class documentation of networksetup::netplan.
#
# * `mode`                 - bonding mode, as understood by the kernel driver
# * `lacp-rate`            - how often to transmit LACPDUs; 802.3ad only
# * `mii-monitor-interval` - link monitoring interval in milliseconds
type Networksetup::Netplan::Bond::Parameters = Struct[{
    Optional['mode'] => Enum[
      'balance-rr', 'active-backup', 'balance-xor', 'broadcast',
      '802.3ad', 'balance-tlb', 'balance-alb',
    ],
    Optional['lacp-rate']            => Enum['slow', 'fast'],
    Optional['mii-monitor-interval'] => Integer[0],
}]
