require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_alias).provide(:ip, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network alias.'

  commands ip: 'ip'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def config_path
    device = @resource[:device]

    "/etc/sysconfig/network-scripts/ifcfg-#{device}"
  end

  def ifcfg_data
    @addrinfo ||= self.class.parse_config(config_path)
  end

  mk_resource_methods

  def ipv6addr_secondaries
    ifcfg_data['ipv6addr_secondaries'].split.map { |a| a.strip } if ifcfg_data['ipv6addr_secondaries']
  end

  def ifcfg_content
    ifcfg_device = @resource[:device] || device
    ifcfg_ipaddr = @resource[:ipaddr] || ipaddr
    ifcfg_netmask = @resource[:netmask] || netmask
    ifcfg_ipv6addr = @resource[:ipv6addr] || ipv6addr
    ifcfg_ipv6init = @resource[:ipv6init] || ipv6init
    ifcfg_prefix = @resource[:prefix] || prefix
    ifcfg_ipv6addr_secondaries = @resource[:ipv6addr_secondaries] || ipv6addr_secondaries
    ifcfg_type = @resource[:conn_type] || conn_type

    ERB.new(<<-EOF, nil, '<>').result(binding)
<% if ifcfg_device %>
DEVICE=<%= ifcfg_device %>
<% end %>
<% if ifcfg_type %>
TYPE=<%= ifcfg_type %>
<% end %>
<% if ifcfg_ipaddr %>
IPADDR=<%= ifcfg_ipaddr %>
<% end %>
<% if ifcfg_netmask %>
NETMASK=<%= ifcfg_netmask %>
<% end %>
<% if ifcfg_prefix %>
PREFIX=<%= ifcfg_prefix %>
<% end %>
<% if ifcfg_ipv6addr %>
IPV6ADDR=<%= ifcfg_ipv6addr %>
<% end %>
<% if ifcfg_ipv6init %>
IPV6INIT=<%= ifcfg_ipv6init %>
<% end %>
<% if ifcfg_ipv6addr_secondaries %>
IPV6ADDR_SECONDARIES="<%= [ifcfg_ipv6addr_secondaries].flatten.join(' ') %>"
<% end %>
EOF
  end

  def create
    ifcfg_type = @resource[:conn_type] || conn_type

    f = File.open(config_path, 'w', 0o600)
    f.write(ifcfg_content)
    f.close

    return unless ifcfg_type

    ENV['PATH'] = ['/etc/sysconfig/network-scripts', ENV['PATH']].join(':')
    self.class.system_caller('ifup', config_path)
  end

  def destroy
    return unless File.exist?(config_path)

    ENV['PATH'] = ['/etc/sysconfig/network-scripts', ENV['PATH']].join(':')
    self.class.system_caller('ifdown', config_path)
  end

  def exists?
    # device from ifcfg script should be equal to device from resource declaration
    device == @resource[:device]
  end

  def flush
    return if @property_flush.empty?
    create
  end
end
