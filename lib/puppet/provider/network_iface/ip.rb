require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_iface).provide(:ip, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network interfaces.'

  commands ip: 'ip'

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
    provider_caller('-details',  '-o', 'link', 'show', *args)
  end

  def self.provider_list(*args)
    provider_show
  end

  def provider_show
    return @desc if @desc

    dev_opts = [:addrgenmode, :numtxqueues, :numrxqueues, :gso_max_size, :gso_max_segs, :mtu, :master]
    show_opts = [:qdisc, :state, :mode, :group, :qlen]
    link_layer_opts = [:brd, :promiscuity, 'link-netnsid']
    bridge_opts = [:forward_delay, :hello_time, :max_age, :ageing_time, :stp_state, :priority, :vlan_filtering,
    :vlan_protocol, :vlan_default_pvid, :vlan_stats_enabled, :group_fwd_mask, :group_address, :mcast_snooping,
    :mcast_router, :mcast_query_use_ifaddr, :mcast_querier, :mcast_hash_elasticity, :mcast_hash_max,
    :mcast_last_member_count, :mcast_startup_query_count, :mcast_last_member_interval, :mcast_membership_interval,
    :mcast_querier_interval, :mcast_query_interval, :mcast_query_response_interval, :mcast_startup_query_interval,
    :mcast_stats_enabled, :mcast_igmp_version, :mcast_mld_version, :nf_call_iptables, :nf_call_ip6tables,
    :nf_call_arptables]
    vxlan_opts = [:id, :dev, :group, :remote, :local, :ttl, :tos, :df, :flowlabel, :dstport, :ageing, :maxaddress]
    vxlan_flags = [:learning, :nolearning, :proxy, :noproxy, :rsc, :norsc, :l2miss, :nol2miss, :l3miss,
    :nol3miss, :udpcsum, :udp6zerocsumtx, :udp6zerocsumrx, :external, :noudpcsum, :noudp6zerocsumtx,
    :noudp6zerocsumrx, :noexternal, :gbp, :gpe]
    bond_opts = [:state, :mode, :active_slave, :clear_active_slave, :miimon, :updelay, :downdelay, :use_carrier,
    :arp_interval, :arp_validate, :arp_all_targets, :arp_ip_target, :primary, :primary_reselect,
    :fail_over_mac, :xmit_hash_policy, :resend_igmp, :num_grat_arp, :num_unsol_na, :all_slaves_active,
    :min_links, :lp_interval, :packets_per_slave, :tlb_dynamic_lb, :lacp_rate, :ad_select, :ad_user_port_key,
    :ad_actor_sys_prio, :ad_actor_system, :queue_id, :mii_status]
    vlan_opts = [:protocol, :id, 'ingress-qos-map', 'egress-qos-map']
    vlan_flags = [:reorder_hdr, :gvrp, :mvrp, :loose_binding, :bridge_binding]
    bridge_slave_opts = [:state, :priority, :cost, :guard, :hairpin, :fastleave, :root_block, :learning,
    :flood, :proxy_arp, :proxy_arp_wifi, :mcast_router, :mcast_fast_leave, :mcast_flood,
    :mcast_to_unicast, :group_fwd_mask, :neigh_suppress, :vlan_tunnel, :isolated,
    :backup_port]

    name = @resource[:name]
    cmdout = self.class.provider_show(name)

    return {} if cmdout.nil?

    @desc = {}

    # split to lines
    desc_lines = cmdout.split('\\').map { |l| l.strip }

    # 35: docker0:
    @desc['ifindex'], ifname, options_string = desc_lines[0].split(':').map { |o| o.strip }

    # eg bond0.316@bond0
    @desc['ifname'], @desc['ifmaster'] =  ifname.split('@')

    # eg <BROADCAST,MULTICAST,UP,LOWER_UP>
    oflags, *options = options_string.split
    m = oflags.match(%r{<(.*)>})

    # ['BROADCAST', 'MULTICAST', 'UP', 'LOWER_UP']
    @desc['ifflags'] = m[1].split(',') if m

    # mtu 1450 qdisc noqueue master brqcb67e1d3-0b state UP mode DEFAULT group default qlen 1000
    options = Hash[options.each_slice(2).to_a]
    (dev_opts + show_opts).each { |f|
      s = f.to_s
      @desc[s] = options[s].to_s if options[s]
    }

    # link layer settings
    # eg link/ether 22:f0:e3:ea:e8:16
    @desc['link-type'], @desc['link-addr'], *options = desc_lines[1].split.map { |o| o.strip }

    # eg brd ff:ff:ff:ff:ff:ff link-netnsid 9 promiscuity 1
    options = Hash[options.each_slice(2).to_a]
    (link_layer_opts + dev_opts).each do |f|
      s = f.to_s
      @desc[s] = options[s].to_s if options[s]
    end

    if desc_lines.size > 2
      # vxlan id 32 dev brq107ce2d3-68 srcport 0 0 dstport 8472 ageing 300 noudpcsum noudp6zerocsumtx noudp6zerocsumrx
      type, *options = desc_lines[2].split.map { |o| o.strip }

      # eg :vxlan or :veth
      type = type.to_sym
      @desc[type] = {}

      case type
      when :veth
        @desc['type'] = type
        type_opts = dev_opts
      when :bridge
        @desc['type'] = type
        type_opts = bridge_opts + dev_opts
      when :vxlan
        # srcport MIN MAX
        i = options.index('srcport')
        if i
          @desc[type]['srcport'] = { 'min' => options[i + 1], 'max' => options[i + 2] }
          options = options[0...i] + options[i + 3..-1]
        end
        # eg noudpcsum noudp6zerocsumtx noudp6zerocsumrxv
        vxlan_flags.each do |f|
          s = f.to_s
          i = options.index(s)
          if i
            @desc[type][s] = true
            options.delete_at(i)
          end
        end

        @desc['type'] = type
        type_opts = vxlan_opts
      when :bond
        @desc['type'] = type
        type_opts = bond_opts + dev_opts
      when :bond_slave
        # according to man 7 ip - ETYPE := [ TYPE | bridge_slave | bond_slave ]
        @desc['etype'] = type
        type_opts = bond_opts + dev_opts
      when :vlan
        m = nil
        options.each do |o|
          # <REORDER_HDR,LOOSE_BINDING>
          m = o.match(%r{<(.*)>})
          if m
            flags = m[1].split(',').map { |f| f.to_s.downcase }
            vlan_flags.each do |f|
              s = f.to_s
              @desc[type][s] = if flags.include?(s)
                            'on'
                          else
                            'off'
                          end
            end
          end
        end
        options.delete(m[0]) if m

        @desc['type'] = type
        type_opts = vlan_opts + dev_opts
      end

      options = Hash[options.each_slice(2).to_a]
      type_opts.each do |f|
        s = f.to_s
        @desc[type][s] = options[s].to_s if options[s]
      end
    end

    if desc_lines.size > 3
      etype, *options = desc_lines[3].split.map { |o| o.strip }
      @desc['etype'] = etype

      etype = etype.to_sym
      @desc[etype] = {}

      options = Hash[options.each_slice(2).to_a]

      case etype
      when :bridge_slave
        bridge_slave_opts.each do |f|
          s = f.to_s
          @desc[etype][s] = options[s].to_s if options[s]
        end
      end
    end
  end

  def type
    provider_show['type']
  end

  def peer_name
    provider_show['ifmaster']
  end

  def peer_name=(name)
    type = @resource[:type]

    case type
    when :veth
      self.class.provider_set('dev', peer_name, 'type', 'veth', 'peer', 'name', name)
      # rename peer device only if same namespace
      unless provider_show['ifmaster'].match(%r{^if[0-9]+$}) && provider_show['link-netnsid']
    end
  end

  def create
    name = @resource[:name]
    type = @resource[:type]

    case type
    when :veth
      peer_name = @resource[:peer_name]
      # ip link add o-hm0 type veth peer name o-bhm0
      self.class.provider_create(name, 'type', 'veth', 'peer', 'name', peer_name)
    end
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
end
