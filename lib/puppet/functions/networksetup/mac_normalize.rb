Puppet::Functions.create_function(:'networksetup::mac_normalize') do
  dispatch :mac_normalize do
    param 'Networksetup::MACAddress', :addr
  end

  def mac_normalize(addr)
    addr.downcase.tr(':', '-')
  end
end
