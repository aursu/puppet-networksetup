require 'ipaddr'

Puppet::Functions.create_function(:'networksetup::gateway_prediction') do
  dispatch :gateway_prediction do
    param 'Stdlib::IP::Address', :addr
  end

  dispatch :gateway_prediction2 do
    param 'Stdlib::IP::Address', :addr
    param 'Stdlib::IP::Address', :mask
  end

  dispatch :gateway_prediction3 do
    param 'Stdlib::IP::Address', :addr
    param 'Optional[Integer]', :prefix
  end

  def gateway_prediction(addr)
    addr, prefix = addr.split('/', 2)

    if IPAddr.new(addr).ipv6?
      fullmask = 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
      defprefix = 64
    else
      fullmask = '255.255.255.255'
      defprefix = 24
    end

    prefix = defprefix unless prefix
    mask = IPAddr.new(fullmask).mask(prefix.to_i).to_s

    IPAddr.new(addr).mask(mask).succ.to_s
  end

  def gateway_prediction2(addr, mask)
    IPAddr.new(addr).mask(mask).succ.to_s
  end

  def gateway_prediction3(addr, prefix = nil)
    if IPAddr.new(addr).ipv6?
      fullmask = 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
      defprefix = 64
    else
      fullmask = '255.255.255.255'
      defprefix = 24
    end

    prefix = defprefix unless prefix

    mask = IPAddr.new(fullmask).mask(prefix.to_i).to_s unless mask

    IPAddr.new(addr).mask(mask).succ.to_s
  end
end
