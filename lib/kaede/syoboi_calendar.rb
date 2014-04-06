require 'net/http'
require 'cgi'
require 'nokogiri'
require 'kaede/program'

module Kaede
  class SyoboiCalendar
    class HttpError < StandardError
      attr_reader :response
      def initialize(res)
        super("HttpError: status=#{res.code}")
        @response = res
      end
    end


    HOST = 'cal.syoboi.jp'
    PORT = 80

    def initialize
      @http = Net::HTTP.new(HOST, PORT)
    end

    def cal_chk(params = {})
      path = '/cal_chk.php'
      q = params.map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join('=')
      if !q.empty?
        path += '?' + q
      end
      res = @http.get(path)
      case res
      when Net::HTTPOK
        Program.from_xml(Nokogiri::HTML.parse(res.body))
      else
        raise HttpError.new(res)
      end
    end
  end
end
