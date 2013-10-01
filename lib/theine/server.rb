require 'drb/drb'
require 'thread'

PRAILS_BASE_PORT = 11000
PRAILS_MAX_PORT = 11100
MIN_FREE_INSTANCES = 2
RAILS_APP_ROOT = Dir.pwd

class PrailsServer
  include DRb::DRbUndumped

  def initialize
    @instances = []
    @spawning = []

    @available_ports = ((PRAILS_BASE_PORT + 1)..PRAILS_MAX_PORT).to_a
    @check_mutex = Mutex.new
    @instances_mutex = Mutex.new
  end

  def add_instance
    path = File.expand_path('../instance.rb', __FILE__)
    port = @available_ports.shift
    puts "(spawn #{port})"
    spawn("ruby", path, PRAILS_BASE_PORT.to_s, port.to_s, RAILS_APP_ROOT)
    @instances_mutex.synchronize { @spawning << 1 }
  end

  def instance_boot(port)
    puts "+ instance #{port}"

    @instances_mutex.synchronize do
      @spawning.pop
      @instances << port
    end
  end

  def get_port
    add_instance if all_size == 0

    port = nil
    while port.nil? && all_size > 0
      @instances_mutex.synchronize do
        port = @instances.shift
      end
      sleep 0.1 unless port
    end

    Thread.new { check_min_free_instances }

    port
  end

  def check_min_free_instances
    if @check_mutex.try_lock
      # TODO: mutex, and dont do it if already in progress
      # do this in thread
      while all_size < MIN_FREE_INSTANCES
        sleep 0.1 until @instances_mutex.synchronize { @spawning.empty? }
        add_instance
      end
      @check_mutex.unlock
    end
  end

  def all_size
    @instances_mutex.synchronize { @instances.size + @spawning.size }
  end
end

server = PrailsServer.new
DRb.start_service("druby://localhost:#{PRAILS_BASE_PORT}", server)

server.check_min_free_instances
DRb.thread.join
