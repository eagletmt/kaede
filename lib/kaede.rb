require 'kaede/config'
require 'kaede/version'

module Kaede
  def self.configure(&block)
    block.call(config)
  end

  def self.config
    @config ||= Config.new
  end
end
