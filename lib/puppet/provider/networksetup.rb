require 'json'
require 'shellwords'
require 'ipaddr'

#
class Puppet::Provider::NetworkSetup < Puppet::Provider
  def self.ip_comm
    command(:ip)
  end

  def self.system_caller(bin, *args)
    cmd = Puppet::Util.which(bin)
    return nil unless cmd # Если команда не найдена, возвращаем nil

    cmdargs = args.compact.reject(&:empty?).map(&:to_s) # Убираем nil и пустые строки
    cmdline = cmdargs.empty? ? cmd : "#{cmd} #{Shellwords.join(cmdargs)}" # Если аргументов нет, просто вызываем `cmd`

    begin
      cmdout = Puppet::Util::Execution.execute(cmdline).to_s
      return nil if cmdout.nil? || cmdout.empty?
      cmdout
    rescue Puppet::ExecutionFailure => detail
      Puppet.debug "Execution of '#{cmdline}' command failed: #{detail}"
      nil
    end
  end

  def self.ip_caller(*args)
    system_caller(ip_comm, *args)
  end

  def self.nmcli_comm
    command(:nmcli)
  end

  # command(:nmcli) is nil where nmcli is not installed. On a node that cannot
  # happen - the confine keeps the provider from being chosen at all - but it
  # does happen wherever suitability was bypassed, and Puppet::Util.which(nil)
  # raises a TypeError rather than saying anything useful.
  def self.nmcli_caller(*args)
    comm = nmcli_comm
    return nil unless comm

    system_caller(comm, *args)
  end

  # Parse the output of `nmcli --terse --fields all --mode multiline connection
  # show`, with or without a connection id. nmcli prints one property per line
  # as name:value, and prints connections one after another with nothing
  # between them - the field names simply start over - so a name that is
  # already in the record being built begins the next record.
  #
  # Multiline mode escapes nothing: one field per line leaves no ambiguity to
  # escape. Property names never contain a colon, so the first colon is the
  # separator and the rest of the line is the value verbatim - `ipv6.addresses:::1/128`
  # is a real line and it carries ::1/128, as is
  # `TIMESTAMP-REAL:Thu 03 Sep 2026 01:29:26 PM EDT`.
  def self.nmcli_parse_records(cmdout)
    return [] if cmdout.nil? || cmdout.empty?

    records = []
    record = {}

    cmdout.each_line do |line|
      key, value = line.chomp.split(':', 2)

      next if key.nil? || key.empty? || value.nil?

      if record.key?(key)
        records << record
        record = {}
      end

      record[key] = value
    end

    records << record unless record.empty?
    records
  end

  # One connection's properties. `connection show <id>` prints a single record,
  # so this is nmcli_parse_records with the record taken out of the array.
  def self.nmcli_parse(cmdout)
    nmcli_parse_records(cmdout).first || {}
  end

  def self.nmcli_connection_list
    nmcli_parse_records(nmcli_caller('--terse', '--fields', 'all', '--mode', 'multiline', 'connection', 'show'))
  end

  # conn_id is anything nmcli accepts as an identifier - a profile name, a UUID
  # or a D-Bus path. Names are not unique, UUIDs are.
  def self.nmcli_connection_show(conn_id)
    nmcli_parse(nmcli_caller('--terse', '--fields', 'all', '--mode', 'multiline', 'connection', 'show', conn_id))
  end

  # Find a connection by profile name, then by the device it is bound to. A
  # profile's name and its device are independent in NetworkManager - `lo` has
  # both the same, `cloud-init enp1s0` does not - and the ip family addresses
  # interfaces by device, so both have to resolve.
  #
  # A name identifies no more than one connection only by convention. A host
  # can carry two profiles both called eth0, one active and one not, and this
  # returns the active one: it is the profile the system is running on, and the
  # only one a device lookup could find at all, since DEVICE is empty on every
  # inactive profile. A provider that needs to know whether the profile it
  # found is persistent or was generated at runtime has to read FILENAME -
  # /run/NetworkManager holds the generated ones.
  def self.nmcli_connection_lookup(name, device = nil)
    connections = nmcli_connection_list

    named = connections.select { |connection| connection['NAME'] == name }
    conn = named.find { |connection| connection['ACTIVE'] == 'yes' } || named.first
    return conn if conn
    return nil if device.nil? || device.empty?

    connections.find { |connection| connection['DEVICE'] == device }
  end

  # Writes do not go through system_caller, for two reasons measured against
  # NetworkManager 1.56.0.
  #
  # An empty value is how a property is unset: `connection modify <id>
  # ipv4.gateway ''` clears the gateway, exits 0 and prints nothing, and a
  # following `connection show` returns the property empty. system_caller drops
  # empty arguments before it builds the command line, so through it that call
  # would reach nmcli as `... ipv4.gateway` with no value at all.
  #
  # And a failed write has to be seen. nmcli exits non-zero - 2 for an unknown
  # property, 10 for an unknown connection - while a successful modify prints
  # nothing, so system_caller's nil means both "it worked" and "it failed".
  # Here the ExecutionFailure is left to propagate and fail the run.
  def self.nmcli_writer(*args)
    cmd = Puppet::Util.which(nmcli_comm)
    raise Puppet::Error, _('nmcli command not found') unless cmd

    Puppet::Util::Execution.execute("#{cmd} #{Shellwords.join(args.compact.map(&:to_s))}").to_s
  end

  def self.nmcli_connection_add(*args)
    nmcli_writer('connection', 'add', *args)
  end

  def self.nmcli_connection_modify(conn_id, *args)
    nmcli_writer('connection', 'modify', conn_id, *args)
  end

  def self.nmcli_connection_delete(conn_id)
    nmcli_writer('connection', 'delete', conn_id)
  end

  def self.nmcli_connection_up(conn_id)
    nmcli_writer('connection', 'up', conn_id)
  end

  # Apply a profile to the device already running it, without deactivating it.
  # Measured on NetworkManager 1.56.0: an address change reapplies with rc 0
  # and the device stays `100 (connected)` throughout. A change NetworkManager
  # cannot reapply - MTU, and link-level settings generally - exits 6.
  #
  # The message names a property from the same setting group rather than the
  # one that changed ("Can't reapply changes to '802-3-ethernet.s390-nettype'"
  # after modifying the MTU), so there is nothing useful to parse out of it.
  # Applied or not applied is the whole of the information.
  def self.nmcli_device_reapply(device)
    nmcli_writer('device', 'reapply', device)
  end

  def self.link_create(*args)
    ip_caller('link', 'add', *args)
  end

  def self.link_delete(*args)
    ip_caller('link', 'delete', *args)
  end

  def self.link_set(*args)
    ip_caller('link', 'set', *args)
  end

  def self.link_show(*args)
    # -o - output each record on a single line, replacing line feeds with the '\' character.
    ip_caller('-details', '-o', 'link', 'show', *args)
  end

  def self.link_list
    ip_caller('-details', '-o', 'link', 'show')
  end

  def self.addr_create(*args)
    ip_caller('addr', 'add', *args)
  end

  def self.addr_delete(addr, dev)
    ip_caller('addr', 'del', addr, 'dev', dev)
  end

  def self.addr_show(*args)
    ip_caller('-details', '-o', 'addr', 'show', *args)
  end

  # All addresses in the system
  def self.addr_list
    ip_caller('-details', '-o', 'addr', 'show')
  end

  def self.route_list
    ip_caller('-details', '-j', 'route', 'list')
  end

  # parse ip -details -o link show command output
  # return Hash with interface link data or empty Hash
  def self.linkinfo_parse(cmdout)
    return {} if cmdout.nil? || cmdout.empty?

    linkinfo_opts = [:mtu, :qdisc, :master, :state, :mode, :group, :qlen]
    linkinfo_flags = [:xdp]
    linkinfo_opts_next1 = ['link-netns', 'link-netnsid', 'new-netns', 'new-netnsid', 'new-ifindex', :protodown, :promiscuity, :minmtu, :maxmtu]
    linkinfo_opts_next2 = [:addrgenmode, :numtxqueues, :numrxqueues, :gso_max_size, :gso_max_segs, :portname, :portid, :switchid]
    link_layer_opts = [:brd, :peer]

    bridge_opts = [:forward_delay, :hello_time, :max_age, :ageing_time, :stp_state, :priority,
                   :vlan_filtering, :vlan_protocol, :bridge_id,
                   :designated_root, :root_port, :root_path_cost,
                   :topology_change, :topology_change_detected,
                   :hello_timer, :tcn_timer, :topology_change_timer, :gc_timer,
                   :vlan_default_pvid, :vlan_stats_enabled,
                   :group_fwd_mask, :group_address,
                   :mcast_snooping, :mcast_router, :mcast_query_use_ifaddr,
                   :mcast_querier, :mcast_hash_elasticity,
                   :mcast_hash_max, :mcast_last_member_count,
                   :mcast_startup_query_count, :mcast_last_member_interval,
                   :mcast_membership_interval, :mcast_querier_interval,
                   :mcast_query_interval, :mcast_query_response_interval,
                   :mcast_startup_query_interval, :mcast_stats_enabled,
                   :mcast_igmp_version, :mcast_mld_version,
                   :nf_call_iptables, :nf_call_ip6tables, :nf_call_arptables]

    vxlan_opts  = [:id, :group, :remote, :local, :dev, :dstport, :tos, :ttl, :df, :flowlabel, :ageing, :maxaddr]
    vxlan_flags = [:learning, :nolearning, :proxy, :rsc, :l2miss, :l3miss, :udpcsum, :udp6zerocsumtx, :udp6zerocsumrx, :remcsumtx, :remcsumrx, :external, :gbp, :gpe]

    bond_opts = [:active_slave, :miimon, :updelay, :downdelay, :use_carrier, :arp_interval, :arp_ip_target,
                 :arp_validate, :arp_all_targets, :primary, :primary_reselect, :fail_over_mac,
                 :xmit_hash_policy, :resend_igmp, :num_grat_arp, :all_slaves_active, :min_links, :lp_interval,
                 :packets_per_slave, :lacp_rate, :ad_select, :ad_aggregator, :ad_num_ports, :ad_actor_key,
                 :ad_actor_sys_prio, :ad_user_port_key, :ad_partner_key, :ad_actor_system, :tlb_dynamic_lb]

    bond_slave_opts = [:state, :mii_status, :link_failure_count, :perm_hwaddr, :queue_id,
                       :ad_aggregator_id, :ad_actor_oper_port_state, :ad_partner_oper_port_state]

    bridge_slave_opts = [:state, :priority, :cost,
                         :hairpin, :guard, :root_block, :fastleave, :learning, :flood,
                         :port_id, :port_no, :designated_port, :designated_cost, :designated_bridge,
                         :designated_root, :hold_timer, :message_age_timer, :forward_delay_timer,
                         :topology_change_ack, :config_pending,
                         :proxy_arp, :proxy_arp_wifi,
                         :mcast_router,
                         :mcast_fast_leave, :mcast_flood]

    vlan_opts = [:protocol, :id]
    vlan_flags = [:reorder_hdr, :gvrp, :mvrp, :loose_binding, :bridge_binding]

    tun_opts = [:type, :pi, :vnet_hdr, :numqueues, :numdisabled, :persist, :user, :group]
    tun_flags = [:multi_queue]

    iptun_opts = [:remote, :local, :dev, :ttl, :tos, '6rd-prefix', '6rd-relay_prefix', :encap, 'encap-sport', 'encap-dport']
    iptun_flags = [:pmtudisc, :nopmtudisc, :isatap, 'encap-csum', 'noencap-csum', 'encap-csum6', 'noencap-csum6', 'encap-remcsum', 'noencap-remcsum']

    ip6tnl_opts = [:remote, :local, :dev, :encaplimit, :hoplimit, :tclass, :flowlabel, :dscp, :fwmark, :encap, 'encap-sport', 'encap-dport']
    ip6tnl_flags = [:mip6, 'encap-csum', 'noencap-csum', 'encap-csum6', 'noencap-csum6', 'encap-remcsum', 'noencap-remcsum']

    desc = {}

    # split to lines
    desc_lines = cmdout.split('\\').map { |l| l.strip }

    # 35: docker0:
    desc['ifi_index'], ifname, options_string = desc_lines[0].split(':').map { |o| o.strip }

    # interface  name
    # eg bond0.316@bond0
    desc['ifname'], desc['iflink'] =  ifname.split('@')

    # eg <BROADCAST,MULTICAST,UP,LOWER_UP>
    link_flags, *options = options_string.split
    m = link_flags.match(%r{<(.*)>})

    # ['BROADCAST', 'MULTICAST', 'UP', 'LOWER_UP']
    desc['link-flags'] = m[1].split(',') if m

    linkinfo_flags.each do |f|
      s = f.to_s
      i = options.index(s)
      if i
        desc[s] = true
        options.delete_at(i)
      end
    end

    # mtu 1450 qdisc noqueue master brqcb67e1d3-0b state UP mode DEFAULT group default qlen 1000
    options = Hash[options.each_slice(2).to_a]
    (linkinfo_opts + linkinfo_opts_next1 + linkinfo_opts_next2).each do |f|
      s = f.to_s
      desc[s] = options[s].to_s if options[s]
    end

    # 207: ppp0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1400 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 3
    #    link/ppp  promiscuity 0 minmtu 0 maxmtu 0
    #    ppp addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
    #
    # Link layer settings
    # eg link/ether 22:f0:e3:ea:e8:16

    # remove leading spaces
    desc['link-type'], *options_linkinfo = desc_lines[1].split.map { |o| o.strip }

    if desc_lines[1].split('  ').size == 1
      desc['link-addr'], *options = options_linkinfo
    else
      desc['link-addr'] = ''
      options = options_linkinfo
    end

    # eg brd ff:ff:ff:ff:ff:ff link-netnsid 9 promiscuity 1
    options = Hash[options.each_slice(2).to_a]
    (link_layer_opts + linkinfo_opts_next1 + linkinfo_opts_next2).each do |f|
      s = f.to_s
      desc[s] = options[s].to_s if options[s]
    end

    if desc_lines.size > 2
      # vxlan id 32 dev brq107ce2d3-68 srcport 0 0 dstport 8472 ageing 300 noudpcsum noudp6zerocsumtx noudp6zerocsumrx
      link_kind, *options = desc_lines[2].split.map { |o| o.strip }

      # eg :vxlan or :veth
      link_kind = link_kind.to_sym
      desc[link_kind] = {}

      link_kind_opts = []
      case link_kind
      when :veth, :ppp
        desc['link-kind'] = link_kind
      when :bridge
        desc['link-kind'] = link_kind
        link_kind_opts = bridge_opts
      when :bridge_slave
        desc['slave-kind'] = link_kind
        link_kind_opts = bridge_slave_opts
      when :vxlan
        # srcport MIN MAX
        i = options.index('srcport')
        if i
          desc[link_kind]['srcport'] = { 'min' => options[i + 1], 'max' => options[i + 2] }
          options = options[0...i] + options[i + 3..-1]
        end

        vxlan_flags.each do |f|
          s = f.to_s
          i = options.index(s)
          next unless i

          if options[i + 1].to_s == 'no'
            desc[link_kind][s] = 'no'
            options = options[0...i] + options[i + 2..-1]
          else
            desc[link_kind][s] = 'yes'
            options.delete_at(i)
          end
        end

        desc['link-kind'] = link_kind
        link_kind_opts = vxlan_opts
      when :bond
        desc['link-kind'] = link_kind
        link_kind_opts = bond_opts
      when :bond_slave
        # according to man 7 ip - ETYPE := [ TYPE | bridge_slave | bond_slave ]
        desc['slave-kind'] = link_kind
        link_kind_opts = bond_slave_opts
      when :vlan
        m = nil
        options.each do |o|
          # <REORDER_HDR,LOOSE_BINDING>
          m = o.match(%r{<(.*)>})

          next unless m

          flags = m[1].split(',').map { |f| f.to_s.downcase }
          vlan_flags.each do |f|
            s = f.to_s
            desc[link_kind][s] = if flags.include?(s)
                                   'on'
                                 else
                                   'off'
                                 end
          end
        end
        options.delete(m[0]) if m

        desc['link-kind'] = link_kind
        link_kind_opts = vlan_opts
      when :tun
        tun_flags.each do |f|
          s = f.to_s
          i = options.index(s)
          if i
            desc[link_kind][s] = 'on'
            options.delete_at(i)
          end
        end

        desc['link-kind'] = link_kind
        link_kind_opts = tun_opts
      when :ipip, :sit
        iptun_flags.each do |f|
          s = f.to_s
          i = options.index(s)
          if i
            desc[link_kind][s] = 'on'
            options.delete_at(i)
          end
        end

        desc['link-kind'] = link_kind
        link_kind_opts = iptun_opts
      when :ip6tnl
        if ['ipip6', 'ip6ip6', 'any'].include?(options[0].to_s)
          desc[link_kind]['ipproto'], *options = options
        end

        i = options.index('(flowinfo')
        if i
          desc[link_kind]['flowinfo'] = options[i + 1].delete(')')
        end

        ip6tnl_flags.each do |f|
          s = f.to_s
          i = options.index(s)
          if i
            desc[link_kind][s] = 'on'
            options.delete_at(i)
          end
        end

        desc['link-kind'] = link_kind
        link_kind_opts = ip6tnl_opts
      end

      options = Hash[options.each_slice(2).to_a]
      link_kind_opts.each do |f|
        s = f.to_s
        desc[link_kind][s] = options[s].to_s if options[s]
      end

      linkinfo_opts_next2.each do |o|
        s = o.to_s
        desc[s] = options[s].to_s if options[s]
      end
    end

    # rubocop:disable Metrics/LineLength
    # 188: o-bhm0@o-hm0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop master brqcb67e1d3-0b state DOWN mode DEFAULT group default qlen 1000
    #    link/ether 5e:42:74:a2:8b:6e brd ff:ff:ff:ff:ff:ff promiscuity 1
    #    veth
    #    bridge_slave state disabled priority 32 cost 2 hairpin off guard off root_block off fastleave off learning on flood on port_id 0x8003 port_no 0x3 designated_port 32771 designated_cost 0 designated_bridge 8000.22:f0:e3:ea:e8:16 designated_root 8000.22:f0:e3:ea:e8:16 hold_timer    0.00 message_age_timer    0.00 forward_delay_timer    0.00 topology_change_ack 0 config_pending 0 proxy_arp off proxy_arp_wifi off mcast_router 1 mcast_fast_leave off mcast_flood on addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
    # rubocop:enable Metrics/LineLength
    if desc_lines.size > 3
      slave_kind, *options = desc_lines[3].split.map { |o| o.strip }

      slave_kind = slave_kind.to_sym
      desc[slave_kind] = {}

      slave_kind_opts = []
      case slave_kind
      when :bridge_slave
        desc['slave-kind'] = slave_kind
        slave_kind_opts = bridge_slave_opts
      when :bond_slave
        # according to man 7 ip - ETYPE := [ TYPE | bridge_slave | bond_slave ]
        desc['slave-kind'] = slave_kind
        slave_kind_opts = bond_slave_opts
      end

      options = Hash[options.each_slice(2).to_a]
      slave_kind_opts.each do |f|
        s = f.to_s
        desc[slave_kind][s] = options[s].to_s if options[s]
      end
      linkinfo_opts_next2.each do |o|
        s = o.to_s
        desc[s] = options[s].to_s if options[s]
      end
    end

    desc
  end

  # 632: tun0    inet 10.11.88.1/32 scope global tun0\       valid_lft forever preferred_lft forever
  #
  # return Array of Hashes with addresses from `ip addr` command output in
  # parameter or empty array
  def self.addrinfo_parse(cmdout)
    return [] if cmdout.nil? || cmdout.empty?

    addrinfo_opts = [:brd, :any, :scope, :flags]
    addrinfo_flags = [:temporary, :secondary, :tentative, :deprecated, :home, :nodad, :mngtmpaddr,
                      :noprefixroute, :autojoin, :dynamic, :dadfailed]
    cacheinfo_opts = [:valid_lft, :preferred_lft]

    addr = []

    cmdout.each_line do |a|
      desc_lines = a.split('\\').map { |l| l.strip }

      desc = {}
      desc['ifa_index'], options_string = desc_lines[0].split(':', 2).map { |o| o.strip }

      # address family
      desc['ifname'], desc['ifa_family'], *options_addrinfo = options_string.split.map { |o| o.strip }

      # address family is "family #num" if not inet/inet6/dnet/ipx
      desc['ifa_family'] = options_addrinfo.shift if desc['ifa_family'] == 'family'

      # local address
      ifa_local = options_addrinfo.shift

      # check for remote peer address
      if options_addrinfo[0] == 'peer'
        _peer, ifa_address, *options = options_addrinfo
        desc['peer'], desc['prefixlen'] = ifa_address.split('/')
        desc['local'] = ifa_local
      else
        options = options_addrinfo
        desc['local'], desc['prefixlen'] = ifa_local.split('/')
      end

      addrinfo_flags.each do |f|
        s = f.to_s
        i = options.index(s)
        if i
          desc[s] = 'on'
          options.delete_at(i)
        end
      end

      # check and set address label
      if (options.size % 2).odd?
        desc['ifa_label'] = options.pop
      end

      options = Hash[options.each_slice(2).to_a]
      addrinfo_opts.each do |f|
        s = f.to_s
        desc[s] = options[s].to_s if options[s]
      end

      options = desc_lines[1].split.map { |o| o.strip }
      options = Hash[options.each_slice(2).to_a]
      cacheinfo_opts.each do |f|
        s = f.to_s
        desc[s] = options[s].to_s if options[s]
      end
      addr += [desc]
    end

    addr
  end

  # return Hash with interface link data or empty Hash
  def self.linkinfo_show(name)
    return {} if name.nil? || name.empty?

    cmdout = link_show(name)
    return {} if cmdout.nil?

    linkinfo_parse(cmdout)
  end

  # return Array of Hashes with addresses for specified interface (via
  # parameter `name`) or mpty array
  def self.addrinfo_show(name)
    return [] if name.nil? || name.empty?

    cmdout = addr_show(name)
    return [] if cmdout.nil?

    addrinfo_parse(cmdout)
  end

  #
  # return Array of Hashes with addresses from `ip addr` command output in
  # parameter or empty array
  def self.routeinfo_parse(cmdout)
    return [] unless cmdout.is_a?(String)
    return [] if cmdout.empty?

    begin
      JSON.parse(cmdout)
    rescue JSON::ParserError => e
      Puppet.debug "Failed to parse JSON from command output: #{e.message}"
      []
    end
  end

  def self.route_delete(dst, dev = nil, gateway = nil)
    raise Puppet::Error, 'Destination is required for route deletion' if dst.nil? || dst.empty?

    args = ['route', 'del', dst]
    args += ['dev', dev] unless dev.nil? || dev.empty?
    args += ['via', gateway] unless gateway.nil? || gateway.empty?

    Puppet.debug "Executing: ip #{args.join(' ')}"
    ip_caller(*args)
  end

  def self.route_create(dst, dev = nil, gateway = nil)
    raise Puppet::Error, 'Destination is required for route creation' if dst.nil? || dst.empty?

    args = ['route', 'add', dst]
    args += ['dev', dev] unless dev.nil? || dev.empty?
    args += ['via', gateway] unless gateway.nil? || gateway.empty?

    Puppet.debug "Executing: ip #{args.join(' ')}"
    ip_caller(*args)
  end

  # return Array of Hashes with routing information
  def self.routeinfo_show
    routeinfo_parse(route_list)
  end

  # return address info for address in parameter or empty hash
  def self.addr_lookup(addr)
    return {} if addr.nil? || addr.empty?

    addrinfo = addrinfo_parse(addr_list).select { |info| info['local'] == addr }

    addrinfo[0] || {}
  end

  # Finds all IP addresses that belong to a specified network.
  #
  # This method retrieves a list of all IP addresses on the system
  # and returns an array of hashes containing information about those
  # that are part of the given network.
  #
  # @param addr [String] The network in CIDR format (e.g., "192.168.1.0/24" or "2001:db8::/64").
  # @return [Array<Hash>] An array of hashes containing information about the matching IP addresses.
  #
  # Example usage:
  #   addr_lookup_net("192.168.1.0/24")
  #   => [
  #        {
  #          "ifa_index" => "2",
  #          "ifname" => "eth0",
  #          "ifa_family" => "inet",
  #          "local" => "192.168.1.100",
  #          "prefixlen" => "24",
  #          "scope" => "global",
  #          "dynamic" => "on",
  #          "valid_lft" => "12345",
  #          "preferred_lft" => "56789"
  #        }
  #      ]
  # The label the kernel carries for an address - what `ip a` shows as
  # lo:myspc. NetworkManager's address list has no room for one, so on a
  # release it stores, a label is live state only: the profile carries the
  # address and the label is put on it afterwards.
  def self.addr_label(addr)
    addr_lookup(addr)['ifa_label']
  end

  def self.addr_lookup_net(addr)
    return [] if addr.nil? || addr.empty?

    network = IPAddr.new(addr) # Create an IPAddr object for the network

    addrinfo_parse(addr_list).select { |info| network.include?(IPAddr.new(info['local'])) }
  end

  # return String (hardware address) or nil
  def self.get_hwaddr(name)
    syspath = "/sys/class/net/#{name}"
    if File.exist?("#{syspath}/address")
      File.read("#{syspath}/address").upcase
    elsif File.exist?(syspath)
      desc = linkinfo_show(name)
      desc['link-addr']&.upcase
    else
      nil
    end
  end

  # return either String (path to configuration file) or nil
  def self.config(name, conn_name = nil)
    # NAME inside ifcfg file could be different than name for device
    conn_name = name if conn_name.nil?
    if File.exist?("/etc/sysconfig/network-scripts/#{name}")
      "/etc/sysconfig/network-scripts/#{name}"
    elsif File.exist?("/etc/sysconfig/network-scripts/ifcfg-#{name}")
      "/etc/sysconfig/network-scripts/ifcfg-#{name}"
    else
      # try to find config file by NAME
      ifcfg = get_config_by_name(conn_name)

      # try to find config file by HWADDR
      unless ifcfg
        addr = get_hwaddr(name)
        ifcfg = get_config_by_hwaddr(addr) if addr
      end

      # no need to lookup it again using same name
      return ifcfg if name == conn_name

      # try to find config file by DEVICE
      unless ifcfg
        ifcfg = get_config_by_device(name)
      end
      ifcfg
    end
  end

  def self.validate_ip(ip)
    return nil unless ip
    IPAddr.new(ip)
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    nil
  end

  def self.validate_mac(mac)
    return nil unless mac
    %r{^([a-f0-9]{2}[:-]){5}[a-f0-9]{2}$} =~ mac.downcase
  end

  def self.validate_netmask(netmask)
    mask = IPAddr.new(netmask).to_i

    # 0.0.0.0
    return false if mask.zero?

    mask >>= 1 while (mask + 1) & mask == mask

    return false if mask.to_s(2).count('0') >= 1
    mask
  rescue IPAddr::InvalidAddressError
    nil
  end

  def self.netmask_prefix(netmask)
    mask = validate_netmask(netmask)
    return nil unless mask

    mask.to_s(2).size
  end

  def validate_ip(ip)
    self.class.validate_ip(ip)
  end

  def validate_mac(mac)
    self.class.validate_mac(mac)
  end

  def validate_netmask(netmask)
    self.class.validate_netmask(netmask)
  end

  def netmask_prefix(netmask)
    self.class.netmask_prefix(netmask)
  end

  # return Hash of innterface script parameters with empty hash if no any info
  def self.parse_config(ifcfg)
    desc = {}

    map = {
      'ARPCHECK'  => 'arpcheck',
      'BOOTPROTO' => 'bootproto',
      'BROADCAST' => 'broadcast',
      'DEVICE'    => 'device',
      'DEFROUTE'  => 'defroute',
      'DNS1'      => 'dns',
      'DNS2'      => 'dns',
      'GATEWAY'   => 'gateway',
      'HWADDR'    => 'hwaddr',
      'IPADDR'    => 'ipaddr',
      'IPV6ADDR'  => 'ipv6addr',
      'IPV6INIT'  => 'ipv6init',
      'IPV6_DEFAULTGW' => 'ipv6_defaultgw',
      'IPV6_DEFROUTE'  => 'ipv6_defroute',
      'IPV6ADDR_SECONDARIES' => 'ipv6addr_secondaries',
      'IPV6_AUTOCONF'        => 'ipv6_autoconf',
      'MASTER'    => 'master',
      'NAME'      => 'conn_name',
      'NETMASK'   => 'netmask',
      'NETWORK'   => 'network',
      'NM_CONTROLLED' => 'nm_controlled',
      'ONBOOT'    => 'onboot',
      'PREFIX'    => 'prefix',
      'SLAVE'     => 'slave',
      'TYPE'      => 'conn_type',
      'UUID'      => 'uuid',
    }

    return {} unless ifcfg && File.exist?(ifcfg)

    data = File.read(ifcfg)
    data.each_line do |line|
      # skip comments
      next if line.match?(%r{^\s*#})

      p, v = line.split('=', 2)
      k = map[p]

      next unless k

      s = v.strip
           .sub(%r{^['"]}, '')
           .sub(%r{['"]$}, '')

      if k == 'dns'
        desc[k] ||= []
        desc[k] << s
      else
        desc[k] = s
      end
    end

    desc
  end

  # The counterpart of parse_config: one connection's nmcli properties, named
  # the way the types name them.
  #
  # Two differences from parse_config shape the rules below. nmcli prints
  # *every* property of a profile, so a blank value means unset, where an ifcfg
  # file simply has no such line. And NetworkManager keeps one fact once where
  # ifcfg kept it twice - an address carries its prefix, and there is no
  # netmask at all.
  #
  # Where the two notations are isomorphic the value is derived: a netmask is a
  # prefix written differently, and reporting nil for it would leave a resource
  # that declares one permanently out of sync, rewriting the profile on every
  # run. Where the mapping loses meaning it stays nil instead: ipv4.method
  # disabled, link-local and shared have no BOOTPROTO to be, and inventing one
  # would be a lie rather than a translation.
  # `primary` names the addresses the resource asking considers its own. The
  # order of ipv4.addresses says nothing: on a web node whose aliases came from
  # ifcfg files, 127.0.0.1/8 is the *last* entry of the loopback connection and
  # the service addresses precede it. So an address the resource declares is
  # its primary wherever it sits in the list, and only when it declares none,
  # or names one that is not there, does position decide.
  def self.nmcli_properties(desc, primary = {})
    return {} if desc.nil? || desc.empty?

    read = ->(key) { (desc[key].nil? || desc[key].empty?) ? nil : desc[key] }
    invert = ->(key) { read.call(key) && ((read.call(key) == 'yes') ? 'no' : 'yes') }

    addr, *secondaries = address_list(read.call('ipv4.addresses'), primary['ipaddr'])
    addr, prefix = addr.to_s.split('/')
    ipv6addr, *ipv6_secondaries = address_list(read.call('ipv6.addresses'), primary['ipv6addr'])
    ipv6addr, ipv6_prefixlength = ipv6addr.to_s.split('/')
    ipv4_method = read.call('ipv4.method')
    ipv6_method = read.call('ipv6.method')

    {
      'conn_name' => read.call('connection.id'),
      'uuid' => read.call('connection.uuid'),
      'device' => read.call('connection.interface-name'),
      'conn_type' => nm_type_to_conn_type(read.call('connection.type')),
      'onboot' => read.call('connection.autoconnect'),
      # renamed in NetworkManager 1.5x: EL8 and EL9 say master, EL10 controller
      'master' => read.call('connection.controller') || read.call('connection.master'),
      'slave' => (read.call('connection.port-type') || read.call('connection.slave-type')) && 'yes',
      # NetworkManager's own word, not a translation: manual and none name the
      # same state but disabled names one BOOTPROTO cannot, and the type knows
      # the two vocabularies are equivalent where they overlap.
      'bootproto' => ipv4_method,
      'ipaddr' => addr,
      'ipaddr_secondaries' => secondaries.empty? ? nil : secondaries.join(' '),
      'prefix' => prefix,
      'netmask' => prefix && IPAddr.new('255.255.255.255').mask(prefix.to_i).to_s,
      'gateway' => read.call('ipv4.gateway'),
      'dns' => read.call('ipv4.dns')&.split(',')&.map(&:strip),
      'defroute' => invert.call('ipv4.never-default'),
      'ipv6init' => ipv6_method && ((ipv6_method == 'ignore') ? 'no' : 'yes'),
      'ipv6_autoconf' => ipv6_method && ((ipv6_method == 'auto') ? 'yes' : 'no'),
      'ipv6addr' => ipv6addr,
      'ipv6_prefixlength' => ipv6_prefixlength,
      'ipv6addr_secondaries' => ipv6_secondaries.empty? ? nil : ipv6_secondaries.join(' '),
      'ipv6_defaultgw' => read.call('ipv6.gateway'),
      'ipv6_defroute' => invert.call('ipv6.never-default'),
      'hwaddr' => read.call('802-3-ethernet.mac-address'),
      # arpcheck, broadcast, network, nm_controlled and parent_device have no
      # NetworkManager counterpart. Broadcast and network are derived by the
      # kernel, and a profile is managed by NetworkManager by definition, so
      # NM_CONTROLLED has nothing to say.
    }.compact
  end

  # The inverse of nmcli_properties: properties named the way the types name
  # them, as arguments to `nmcli connection modify`. Takes the whole set rather
  # than one at a time, because several of them are one nmcli property between
  # them - an address and its prefix, an IPv6 primary and its secondaries.
  #
  # Values are written whole. nmcli would also take +property and -property to
  # append or remove list items, but the result of those depends on what was
  # there before, which is the opposite of what a provider wants: Puppet
  # declares a state, and writing the whole value reaches it in one step from
  # wherever the profile happened to be.
  def self.nmcli_arguments(props)
    args = []

    args += ['connection.id', props['conn_name']] if props.key?('conn_name')
    args += ['connection.interface-name', props['device']] if props.key?('device')
    args += ['connection.autoconnect', switch_to_bool_str(props['onboot'])] if props.key?('onboot')
    args += ['802-3-ethernet.mac-address', props['hwaddr'].to_s] if props.key?('hwaddr')

    args += ['ipv4.method', bootproto_to_nm_method(props['bootproto'])] if props['bootproto']
    args += ['ipv4.addresses', ipv4_address_argument(props)] if props.key?('ipaddr')
    args += ['ipv4.gateway', props['gateway'].to_s] if props.key?('gateway')
    args += ['ipv4.dns', [props['dns']].flatten.compact.join(',')] if props.key?('dns')
    args += ['ipv4.never-default', invert_switch(props['defroute'])] if props['defroute']

    args += ['ipv6.method', ipv6_method_argument(props)] if props['ipv6init'] || props['ipv6_autoconf']
    args += ['ipv6.addresses', ipv6_address_argument(props)] if props.key?('ipv6addr')
    args += ['ipv6.gateway', props['ipv6_defaultgw'].to_s] if props.key?('ipv6_defaultgw')
    args += ['ipv6.never-default', invert_switch(props['ipv6_defroute'])] if props['ipv6_defroute']

    args
  end

  # An address and its prefix are one value. A netmask is accepted in its
  # place, since the two are the same fact written differently, and an ifcfg
  # era manifest is as likely to carry one as the other.
  def self.ipv4_address_argument(props)
    addr = props['ipaddr'].to_s
    return '' if addr.empty?

    prefix = props['prefix'] || (props['netmask'] && IPAddr.new("#{addr}/#{props['netmask']}").prefix)
    primary = prefix ? "#{addr}/#{prefix}" : addr

    ([primary] + secondary_list(props['ipaddr_secondaries'])).join(', ')
  end

  # Secondaries arrive as an array from a resource and as a space-separated
  # string from ifcfg_data, since that is the shape IPV6ADDR_SECONDARIES had.
  def self.secondary_list(value)
    [value].flatten.compact.map(&:to_s).flat_map(&:split)
  end

  # ifcfg named the first address and the rest separately; NetworkManager has
  # one list and treats its first entry as the primary. The order is therefore
  # meaningful and is preserved exactly as given.
  def self.ipv6_address_argument(props)
    primary = props['ipv6addr'].to_s
    return '' if primary.empty?

    primary = [primary, props['ipv6_prefixlength']].compact.join('/') unless primary.include?('/') || props['ipv6_prefixlength'].nil?
    ([primary] + secondary_list(props['ipv6addr_secondaries'])).join(', ')
  end

  # IPV6INIT and IPV6_AUTOCONF were two switches; ipv6.method is one word.
  # Off wins over everything, autoconfiguration over a static address, and a
  # profile that says neither is left to autoconfigure, which is what
  # NetworkManager does by default.
  def self.ipv6_method_argument(props)
    return 'ignore' if switch_state(props['ipv6init']) == 'no'
    return 'auto' if switch_state(props['ipv6_autoconf']) == 'yes'
    return 'manual' unless props['ipv6addr'].to_s.empty?

    'auto'
  end

  def self.bootproto_to_nm_method(value)
    {
      'none' => 'manual',
      'static' => 'manual',
      'dhcp' => 'auto',
      'bootp' => 'auto',
    }.fetch(value.to_s, value.to_s)
  end

  SWITCH_ON = ['yes', 'true', '1'].freeze
  SWITCH_OFF = ['no', 'false', '0'].freeze

  # A switch is on or off and there is no third answer, so anything else
  # raises rather than being read as off. Values reaching here come from the
  # system as well as from a manifest - the type validates what a manifest
  # says, but an ifcfg file written by hand can carry ONBOOT=True, which
  # initscripts accepts - and reading that as "no" would turn off the
  # autoconnect of a live interface and report success. Case is ignored for
  # the same reason.
  def self.switch_to_bool_str(value)
    return 'yes' if SWITCH_ON.include?(value.to_s.downcase)
    return 'no' if SWITCH_OFF.include?(value.to_s.downcase)

    raise Puppet::Error, _("\"#{value}\" is not a yes/no value")
  end

  # yes, no, or nil for a switch that was not set at all - which is not the
  # same as being set to no. switch_to_bool_str answers a two-state question
  # and reads an unset switch as no, which is right where a value is being
  # written and wrong where the absence of one has to mean "say nothing".
  def self.switch_state(value)
    return nil if value.nil? || value.to_s.empty?

    switch_to_bool_str(value)
  end

  def self.invert_switch(value)
    (switch_to_bool_str(value) == 'yes') ? 'no' : 'yes'
  end

  # nmcli has a third vocabulary. `connection add type ethernet` produces a
  # profile that reports `connection.type:802-3-ethernet`, measured on
  # NetworkManager 1.56.0, so the word used to create a connection is not the
  # word used to read one back.
  #
  # A conn_type with no NetworkManager equivalent raises instead of being
  # passed through: nmcli would reject it anyway, and saying which value is
  # the problem is more use than its error.
  NMCLI_ADD_TYPE = {
    'ethernet' => 'ethernet',
    '802-3-ethernet' => 'ethernet',
    'wireless' => 'wifi',
    'infiniband' => 'infiniband',
    'bridge' => 'bridge',
    'bond' => 'bond',
    'team' => 'team',
    'vlan' => 'vlan',
    'vrf' => 'vrf',
    'vxlan' => 'vxlan',
    'macvlan' => 'macvlan',
    'ip-tunnel' => 'ip-tunnel',
    'wireguard' => 'wireguard',
    'loopback' => 'loopback',
    'dummy' => 'dummy',
    'tun' => 'tun',
    'veth' => 'veth',
  }.freeze

  def self.nmcli_add_type(conn_type)
    type = NMCLI_ADD_TYPE[conn_type.to_s.downcase]
    return type if type

    raise Puppet::Error,
          _("conn_type \"#{conn_type}\" has no NetworkManager equivalent, so a profile cannot be created for it. " \
            'Give a conn_type NetworkManager knows, such as Ethernet or Bridge.')
  end

  # An address list with the resource's own address first, whatever order
  # NetworkManager reports it in.
  def self.address_list(value, primary = nil)
    addresses = value.to_s.split(',').map(&:strip).reject(&:empty?)
    return addresses if primary.nil? || primary.to_s.empty?

    own = addresses.find { |a| a.split('/').first == primary.to_s.split('/').first }
    own ? [own] + (addresses - [own]) : addresses
  end

  def self.nm_type_to_conn_type(type)
    {
      '802-3-ethernet' => 'Ethernet',
      'bridge' => 'Bridge',
      'infiniband' => 'InfiniBand',
      'vlan' => 'Vlan',
    }.fetch(type, type)
  end

  # BOOTPROTO has no word for NetworkManager's disabled, link-local or shared.
  # A provider that stores its configuration in an ifcfg file says so instead
  # of writing a line initscripts would ignore, which would leave the node
  # configured differently from what was declared, and reported as correct.
  IFCFG_UNKNOWN_BOOTPROTO = ['disabled', 'link-local', 'shared'].freeze

  # TYPE in an ifcfg file names the device types initscripts knew. The types
  # only NetworkManager has are refused for the same reason a bootproto it
  # cannot express is: a line initscripts ignores leaves the node configured
  # differently from what was declared, and reported as correct.
  IFCFG_UNKNOWN_CONN_TYPE = ['802-3-ethernet', 'loopback', 'dummy', 'tun', 'veth',
                             'bond', 'team', 'vlan', 'vrf', 'vxlan', 'macvlan',
                             'ip-tunnel', 'wireguard'].freeze

  def self.ifcfg_conn_type(value)
    return value unless IFCFG_UNKNOWN_CONN_TYPE.include?(value.to_s)

    raise Puppet::Error,
          _("conn_type \"#{value}\" has no TYPE equivalent and cannot be written to an ifcfg file. " \
            'It is available on releases managed through NetworkManager.')
  end

  # ifcfg had no IPADDR_SECONDARIES. Additional IPv4 addresses were alias files
  # of their own, which is what network_alias is, so a list here has nowhere to
  # be written and saying so beats writing a line initscripts ignores.
  def self.ifcfg_secondaries(value)
    return value if value.nil? || [value].flatten.compact.empty?

    raise Puppet::Error,
          _('ipaddr_secondaries cannot be written to an ifcfg file, which has no key for a list of ' \
            'addresses. Use network_alias for the additional addresses, or a release managed ' \
            'through NetworkManager.')
  end

  def self.ifcfg_bootproto(value)
    return value unless IFCFG_UNKNOWN_BOOTPROTO.include?(value.to_s)

    raise Puppet::Error,
          _("bootproto \"#{value}\" has no BOOTPROTO equivalent and cannot be written to an ifcfg file. " \
            'It is available on releases managed through NetworkManager.')
  end

  # return Array of paths or empty array if there are no compatible paths
  def self.config_all
    Dir.glob('/etc/sysconfig/network-scripts/ifcfg-*').reject do |config|
      config =~ %r{(~|\.(bak|old|orig|rpmnew|rpmorig|rpmsave))$}
    end
  end

  # return either String (path to configuration file) or nil
  def self.get_config_by_name(name)
    config_all.each do |config|
      desc = parse_config(config)
      return config if desc['conn_name']&.casecmp?(name)
    end
    nil
  end

  # return either String (path to configuration file) or nil
  def self.get_config_by_hwaddr(addr)
    config_all.each do |config|
      desc = parse_config(config)
      return config if desc['hwaddr']&.casecmp?(addr)
    end
    nil
  end

  # return either String (path to configuration file) or nil
  def self.get_config_by_device(device)
    config_all.each do |config|
      desc = parse_config(config)
      return config if desc['device'] == device
    end
    nil
  end

  # return String with device name or nil
  def self.get_device_by_hwaddr(addr)
    ifname = nil

    return ifname if addr.nil? || addr.empty?

    cmdout = link_list
    return ifname unless cmdout

    link = []
    cmdout.each_line do |line|
      link << linkinfo_parse(line)
    end

    linkinfo = {}
    link.each do |info|
      linkinfo = info if info['link-addr']&.casecmp?(addr)
    end

    ifname = linkinfo['ifname'] if linkinfo && linkinfo['ifname']
    ifname
  end

  # Finds network interfaces that have IP addresses belonging to the specified network.
  #
  # This method retrieves all IP addresses from the system and returns a list of
  # unique network interfaces (`ifname`) that have addresses within the given CIDR network.
  #
  # @param ref [String] The network in CIDR format (e.g., "192.168.1.0/24" or "2001:db8::/64").
  # @return [Array<String>] An array of unique interface names (`ifname`) that have IPs in the specified network.
  #
  # Example usage:
  #   get_device_by_network("192.168.1.0/24")
  #   => ["eth0"]
  #
  #   get_device_by_network("2001:db8::/64")
  #   => ["wlan0"]
  #
  #   get_device_by_network("10.0.0.0/24")
  #   => []  # No interfaces found in this network
  def self.get_device_by_network(addr)
    devices = []

    addr_lookup_net(addr).each do |info|
      devices << info['ifname'] if info['ifname']
    end

    devices.uniq # Return unique interfaces
  end

  # Every property the types hand to a provider. mk_resource_methods defines a
  # getter and a setter for each, and a provider building a new profile needs
  # to know which of a resource's attributes are properties at all.
  MANAGED_PROPERTIES = [:arpcheck,
                        :bootproto,
                        :ipaddr_secondaries,
                        :broadcast,
                        :conn_name,
                        :conn_type,
                        :defroute,
                        :device,
                        :dns,
                        :gateway,
                        :hwaddr,
                        :ipaddr,
                        :ipv6addr,
                        :ipv6init,
                        :ipv6_defaultgw,
                        :ipv6_defroute,
                        :ipv6addr_secondaries,
                        :ipv6_autoconf,
                        :master,
                        :netmask,
                        :network,
                        :nm_controlled,
                        :onboot,
                        :parent_device,
                        :prefix,
                        :slave,
                        :uuid].freeze

  def self.mk_resource_methods
    MANAGED_PROPERTIES.each do |attr|
      define_method(attr) do
        ifcfg_data[attr.to_s]
      end

      define_method(attr.to_s + '=') do |val|
        @property_flush[attr] = val
      end
    end
  end

  def self.device_type(type)
    case type
    when 'Ethernet', 'Wireless', 'Token Ring'
      :eth
    when 'CIPE'
      :cipcb
    when 'IPSEC'
      :ipsec
    when 'Modem', 'xDSL'
      :ppp
    when 'ISDN'
      :ippp
    when 'CTC'
      :ctc
    when 'GRE', 'IPIP', 'IPIP6'
      :tunnel
    when 'SIT', 'sit'
      :sit
    when 'InfiniBand', 'infiniband'
      :ib
    when %r{^OVS[A-Za-z]*$}
      :ovs
    end
  end
end
