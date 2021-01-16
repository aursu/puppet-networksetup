require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_iface).provide(:ip, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network interfaces.'

  commands ip: 'ip'
  commands brctl: 'brctl'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.provider_create(*args)
    provider_caller('link', 'add', *args)
  end

  def self.provider_delete(*args)
    provider_caller('link', 'delete', *args)
  end

  def self.provider_set(*args)
    provider_caller('link', 'set', *args)
  end

  def self.provider_show(*args)
    # -o - output each record on a single line, replacing line feeds with the '\' character.
    provider_caller('-details', '-o', 'link', 'show', *args)
  end

  def brctl_caller(*args)
    self.class.system_caller(brctl_comm, *args)
  end

  # parse ip -details -o link show command output
  def interface_show(name)
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

    cmdout = self.class.provider_show(name)
    return {} if cmdout.nil?

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
    desc_lines_link = desc_lines[1].strip
    desc['link-type'], *options_addr = desc_lines_link.split.map { |o| o.strip }

    if desc_lines_link.split('  ').size == 1
      desc['link-addr'], *options = options_addr
    else
      desc['link-addr'] = ''
      options = options_addr
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

      case link_kind
      when :veth, :ppp
        desc['link-kind'] = link_kind
        link_kind_opts = []
      when :bridge
        desc['link-kind'] = link_kind
        link_kind_opts = bridge_opts
      when :bridge_slave
        desc['slave-kind'] = slave_kind
        slave_kind_opts = bridge_slave_opts
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
          skip unless i

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

          skip unless m

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

  def provider_show
    name = @resource[:name]

    @desc ||= interface_show(name)
  end

  def create
    name = @resource[:name]
    kind = @resource[:link_kind]

    case kind
    when :veth
      peer_name = @resource[:peer_name]
      # ip link add o-hm0 type veth peer name o-bhm0
      self.class.provider_create(name, 'type', 'veth', 'peer', 'name', peer_name)
    end
  end

  def link_kind
    provider_show['link-kind']
  end

  def peer_name
    provider_show['iflink'] || :absent
  end

  def peer_name=(peer)
    @property_flush[:peer_name] = peer
  end

  def bridge
    if provider_show['etype'] == 'bridge_slave'
      provider_show['master']
    else
      :absent
    end
  end

  def bridge=(brname)
    name = @resource[:name]
    if provider_show['etype'] == 'bridge_slave'
      if brname == :absent
        brctl_caller('delif', brname, name)
      else
        raise Puppet::Error, _("device #{name} is already a member of a bridge") unless provider_show['master'] == brname
      end
    else
      # eg brctl addif brqfc32e1e1-6f o-bhm0
      brctl_caller('addif', brname, name)
    end
    @property_flush[:bridge] = brname
  end

  def destroy
    name = @resource[:name]

    self.class.provider_delete(name)
  end

  def exists?
    name = @resource[:name]
    # no ifname - no  device
    provider_show['ifname'] == name
  end

  def flush
    return if @property_flush.empty?
  end
end
