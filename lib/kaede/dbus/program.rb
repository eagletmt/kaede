require 'dbus'
require 'nokogiri'
require 'time'
require 'kaede/dbus/properties'

module Kaede
  module DBus
    class Program < ::DBus::Object
      PATH = '/cc/wanko/kaede1/program'
      PROPERTY_INTERFACE = 'org.freedesktop.DBus.Properties'
      INTROSPECT_INTERFACE = 'org.freedesktop.DBus.Introspectable'
      PROGRAM_INTERFACE = 'cc.wanko.kaede1.Program'

      def initialize(program, enqueued_at)
        super("#{PATH}/#{program.pid}")
        @program = program
        @enqueued_at = enqueued_at
      end

      include Properties
      properties_for PROGRAM_INTERFACE, :properties
      define_properties

      def to_xml
        Nokogiri::XML::Builder.new do |xml|
          xml.doc.create_internal_subset(
            'node',
            '-//freedesktop//DTD D-BUS Object Introspection 1.0//EN',
            'http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd',
          )
          xml.node do
            xml.interface(name: INTROSPECT_INTERFACE) do
              xml.method_(name: 'Introspect') do
                xml.arg(name: 'data', direction: 'out', type: 's')
              end
            end

            xml_for_properties(xml)
          end
        end.to_xml
      end

      dbus_interface PROGRAM_INTERFACE do
      end

      def properties
        @properties ||= {
          'Pid' => @program.pid,
          'Tid' => @program.tid,
          'StartTime' => @program.start_time.iso8601,
          'EndTime' => @program.end_time.iso8601,
          'ChannelName' => @program.channel_name,
          'ChannelForSyoboi' => @program.channel_for_syoboi,
          'ChannelForRecorder' => @program.channel_for_recorder,
          'Count' => @program.count,
          'StartOffset' => @program.start_offset,
          'SubTitle' => @program.subtitle,
          'Title' => @program.title,
          'Comment' => @program.comment,
          'EnqueuedAt' => @enqueued_at.iso8601,
        }
      end
    end
  end
end
