require 'dbus'

module Kaede
  module DBus
    class Scheduler < ::DBus::Object
      PATH = '/cc/wanko/kaede1/scheduler'
      SCHEDULER_INTERFACE = 'cc.wanko.kaede1.Scheduler'

      def initialize(reload_event, restart_event)
        super(PATH)
        @reload_event = reload_event
        @restart_event = restart_event
      end

      dbus_interface SCHEDULER_INTERFACE do
        dbus_method :Reload do
          @reload_event.incr(1)
          nil
        end

        dbus_method :Restart do
          @restart_event.incr(1)
          nil
        end
      end
    end
  end
end
