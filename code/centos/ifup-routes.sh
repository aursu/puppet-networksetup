#! /bin/bash
#
# adds static routes which go through device $1

if [ -z "$1" ]; then
    echo $"usage: ifup-routes <net-device> [<nickname>]"
    exit 1
fi

MATCH='^[[:space:]]*(\#.*)?$'

handle_file () {
    . $1
    routenum=0
    while [ "x$(eval echo '$'ADDRESS$routenum)x" != "xx" ]; do
        eval $(ipcalc -p $(eval echo '$'ADDRESS$routenum) $(eval echo '$'NETMASK$routenum))
        line="$(eval echo '$'ADDRESS$routenum)/$PREFIX"
        if [ "x$(eval echo '$'GATEWAY$routenum)x" != "xx" ]; then
            line="$line via $(eval echo '$'GATEWAY$routenum)"
        fi
        line="$line dev $2"
        /sbin/ip route add $line
        routenum=$(($routenum+1))
    done
}

handle_ip_file() {
    local f t type= file=$1 proto="-4"
    f=${file##*/}
    t=${f%%-*}
    type=${t%%6}
    if [ "$type" != "$t" ]; then
        proto="-6"
    fi
    { cat "$file" ; echo ; } | while read line; do
        if [[ ! "$line" =~ $MATCH ]]; then
            /sbin/ip $proto $type add $line
        fi
    done
}

FILES="/etc/sysconfig/network-scripts/route-$1 /etc/sysconfig/network-scripts/route6-$1"
if [ -n "$2" -a "$2" != "$1" ]; then
    FILES="$FILES /etc/sysconfig/network-scripts/route-$2 /etc/sysconfig/network-scripts/route6-$2"
fi

for file in $FILES; do
    if [ -f "$file" ]; then
        if grep -Eq '^[[:space:]]*ADDRESS[0-9]+=' $file ; then
            # new format
            handle_file $file ${1%:*}
        else
            # older format
            handle_ip_file $file
        fi
    fi
done


# Red Hat network configuration format
NICK=${2:-$1}
CONFIG="/etc/sysconfig/network-scripts/$NICK.route"
[ -f $CONFIG ] && handle_file $CONFIG $1


# Routing rules
FILES="/etc/sysconfig/network-scripts/rule-$1 /etc/sysconfig/network-scripts/rule6-$1"
if [ -n "$2" -a "$2" != "$1" ]; then
    FILES="$FILES /etc/sysconfig/network-scripts/rule-$2 /etc/sysconfig/network-scripts/rule6-$2"
fi

for file in $FILES; do
    if [ -f "$file" ]; then
        handle_ip_file $file
    fi
done