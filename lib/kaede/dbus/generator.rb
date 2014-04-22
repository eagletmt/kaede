require 'nokogiri'
require 'kaede/dbus'

module Kaede
  module DBus
    class Generator
      def generate_policy(user)
        Nokogiri::XML::Builder.new do |xml|
          xml.comment 'Put this policy configuration file into /etc/dbus-1/system.d'
          xml.doc.create_internal_subset(
            'busconfig',
            '-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN',
            'http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd',
          )
          xml.busconfig do
            xml.policy(user: 'root') do
              xml.allow(own: DESTINATION)
            end
            xml.policy(user: user) do
              xml.allow(own: DESTINATION)
            end

            xml.policy(context: 'default') do
              xml.allow(send_destination: DESTINATION)
              xml.allow(receive_sender: DESTINATION)
            end
          end
        end.to_xml
      end
    end
  end
end
