require 'json'
require 'shellwords'
require 'ipaddr'

#
class Puppet::Provider::NetworkSetup < Puppet::Provider
  initvars

  commands ip: 'ip'
  commands brctl: 'brctl'

  confine true: begin
                  ip('-V')
                rescue Puppet::ExecutionFailure, Puppet::MissingCommand
                  false
                else
                  true
                end

  def self.ip_comm
    command(:ip)
  end

  def self.brctl_comm
    command(:brctl)
  end

  def self.ip_caller(*args)
    system_caller(ip_comm, *args)
  end

  def self.system_caller(bin, *args)
    cmd = Puppet::Util.which(bin)

    cmdargs = Shellwords.join(args)
    cmdline = [cmd, cmdargs].compact.join(' ') if cmd

    cmdout = Puppet::Util::Execution.execute(cmdline) if cmdline
    return nil if cmdout.nil?
    return nil if cmdout.empty?
    return cmdout
  rescue Puppet::ExecutionFailure => detail
    Puppet.debug "Execution of $(#{cmdline}) command failed: #{detail}"
    false
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

  def self.addr_show(*args)
    ip_caller('-details', '-o', 'addr', 'show', *args)
  end

  def self.addr_list(*args)
    ip_caller('-details', '-o', 'addr', 'show')
  end

  # parse ip -details -o link show command output
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

  # 632: tun0    inet 10.11.88.1/32 scope global tun0\       valid_lft forever preferred_lft forever
  def self.addrinfo_parse(cmdout)
    return [] if cmdout.nil? || cmdout.empty?

    addrinfo_opts = [:brd, :any, :scope, :flags]
    addrinfo_flags = [:temporary, :secondary, :tentative, :deprecated, :home, :nodad, :mngtmpaddr,
                      :noprefixroute, :autojoin, :dynamic, :dadfailed]
    cacheinfo_opts = [:valid_lft, :preferred_lft]

    addr = []

    cmdout.each_line { |a|
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
      if options.size % 2 == 1
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
    }

    addr
  end

  def self.linkinfo_show(name)
    cmdout = link_show(name)
    return {} if cmdout.nil?

    linkinfo_parse(cmdout)
  end

  def self.addrinfo_show(name)
    cmdout = addr_show(name)
    return {} if cmdout.nil?

    addrinfo_parse(cmdout)
  end

  def self.get_hwaddr(name)
    syspath = "/sys/class/net/#{name}"
    if File.exist?("#{syspath}/address")
      File.read("#{syspath}/address").upcase
    elsif File.exist?(syspath)
      desc = linkinfo_show(name)
      desc['link-addr'].upcase
    end
    ''
  end

  def self.config(name, conn_name = nil)
    # NAME inside ifcfg file could be different than name for device
    conn_name = name if conn_name.nil?
    if File.exist?(name)
      name
    elsif File.exist?("/etc/sysconfig/network-scripts/#{name}")
      "/etc/sysconfig/network-scripts/#{name}"
    elsif File.exist?("/etc/sysconfig/network-scripts/ifcfg-#{name}")
      "/etc/sysconfig/network-scripts/ifcfg-#{name}"
    else
      # try to find config file by NAME
      ifcfg = get_config_by_name(conn_name)

      # try to find config file by HWADDR
      addr = get_hwaddr(name)
      if ifcfg.empty? && addr
        ifcfg = get_config_by_hwaddr(addr) unless addr.empty?
      end
      # try to find config file by DEVICE
      if ifcfg.nil? || ifcfg.empty?
        ifcfg = get_config_by_device(name)
      end
      ifcfg
    end
  end

  def self.validate_ip(ip)
    return nil unless ip
    IPAddr.new(ip)
  rescue ArgumentError
    nil
  end

  def self.validate_mac(mac)
    return nil unless mac
    %r{^([a-f0-9]{2}[:-]){5}[a-f0-9]{2}$} =~ mac.downcase
  end

  def validate_ip(ip)
    self.class.validate_ip(ip)
  end

  def validate_mac(mac)
    self.class.validate_mac(mac)
  end

  def self.parse_config(ifcfg)
    desc = {}

    map = {
      'BOOTPROTO' => 'bootproto',
      'BROADCAST' => 'broadcast',
      'DEVICE'    => 'device',
      'HWADDR'    => 'hwaddr',
      'IPADDR'    => 'ipaddr',
      'NAME'      => 'conn_name',
      'NETMASK'   => 'netmask',
      'NETWORK'   => 'network',
      'ONBOOT'    => 'onboot',
      'TYPE'      => 'conn_type',
    }

    if ifcfg && File.exist?(ifcfg)
      data = File.read(ifcfg)
      data.each_line do |line|
        # skip comments
        next if line =~ %r{^\s*#}

        p, v = line.split('=', 2)
        k = map[p]
        desc[k] = v.strip
                   .sub(%r{^['"]}, '')
                   .sub(%r{['"]$}, '') if k
      end
    end

    desc
  end

  def self.config_all
    Dir.glob('/etc/sysconfig/network-scripts/ifcfg-*').reject do |config|
      config =~ %r{(~|\.(bak|old|orig|rpmnew|rpmorig|rpmsave))$}
    end
  end

  def self.get_config_by_name(name)
    config_all.each do |config|
      desc = parse_config(config)
      return config if desc['conn_name'].casecmp(name)
    end
    ''
  end

  def self.get_config_by_hwaddr(addr)
    config_all.each do |config|
      desc = parse_config(config)
      return config if desc['hwaddr'].casecmp(addr)
    end
    ''
  end

  def self.get_config_by_device(device)
    config_all.each do |config|
      desc = parse_config(config)
      return config if desc['device'] == device
    end
    ''
  end

  def self.mk_resource_methods
    [:bootproto,
     :broadcast,
     :conn_name,
     :conn_type,
     :device,
     :hwaddr,
     :ipaddr,
     :netmask,
     :network,
     :onboot].each do |attr|
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
