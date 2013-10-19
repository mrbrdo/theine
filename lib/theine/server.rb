require 'drb/drb'
require 'thread'
require 'yaml'
require_relative './config'

module Theine
  class Server
    include DRb::DRbUndumped
    attr_reader :config

    def initialize
      @config = ConfigReader.new(Dir.pwd)

      @workers = []
      @spawning = []

      @available_ports = ((config.base_port + 1)..config.max_port).to_a
      @check_mutex = Mutex.new
      @workers_mutex = Mutex.new

      run
    end

    def add_worker
      path = File.expand_path('../worker.rb', __FILE__)
      port = @available_ports.shift
      puts "(spawn #{port})"
      spawn("screen", "-d", "-m", "-S", "theine#{port}",
        "sh", "-c",
        "ruby #{path} #{config.base_port.to_s} #{port.to_s} #{config.rails_root}; read -p 'Press [Enter] to exit...\n'")
        #"ruby", path, config.base_port.to_s, port.to_s, config.rails_root,
        #"&&", "read", "-p", "Press [Enter] to exit...")
      @workers_mutex.synchronize { @spawning << 1 }
    end

    def worker_boot(port)
      puts "+ worker #{port}"

      @workers_mutex.synchronize do
        @spawning.pop
        @workers << port
      end
    end

    def worker_done(port)
      puts "- worker #{port}"
    end

    def get_port(spawn_new = true)
      add_worker if spawn_new && all_size == 0

      port = @workers_mutex.synchronize do
        @workers.shift
      end

      Thread.new { check_min_free_workers } if spawn_new

      port
    end

    def check_min_free_workers
      if @check_mutex.try_lock
        # TODO: mutex, and dont do it if already in progress
        # do this in thread
        while all_size < config.min_free_workers
          unless config.spawn_parallel
            sleep 0.1 until @workers_mutex.synchronize { @spawning.empty? }
          end
          add_worker
        end
        @check_mutex.unlock
      end
    end

    def all_size
      @workers_mutex.synchronize { @workers.size + @spawning.size }
    end

    def stop_all!
      # TODO: doesn't seem to work
      while port = get_port(false)
        begin
          DRbObject.new_with_uri("druby://localhost:#{port}").stop!
        rescue
        end
      end
    end
  private
    def run
      DRb.start_service("druby://localhost:#{config.base_port}", self)
      check_min_free_workers
      DRb.thread.join
    end
  end
end

begin
  server = Theine::Server.new
ensure
  server.stop_all!
end

