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
      @workers_in_use = []
      @worker_pids = {}
      @spawning_workers = []

      @available_ports = ((config.base_port + 1)..config.max_port).to_a
      @check_mutex = Mutex.new
      @workers_mutex = Mutex.new

      run
    end

    def add_worker
      path = File.expand_path('../worker.rb', __FILE__)
      port = @workers_mutex.synchronize { @available_ports.shift }
      puts "(spawn #{port})"
      spawn("screen", "-d", "-m", "-S", worker_session_name(port),
        "sh", "-c",
        "ruby #{path} #{config.base_port.to_s} #{port.to_s} #{config.rails_root}")
      @workers_mutex.synchronize { @spawning_workers << port }
    end

    def worker_session_name(port)
      "theine#{port}"
    end

    def set_worker_pid(port, pid)
      @workers_mutex.synchronize do
        @worker_pids[port] = pid
      end
    end

    def worker_boot(port)
      puts "+ worker #{port}"

      @workers_mutex.synchronize do
        @spawning_workers.delete(port)
        @workers << port
      end
    end

    def worker_done(port)
      puts "- worker #{port}"
      @workers_mutex.synchronize do
        @workers_in_use.delete(port)
        @available_ports << port
      end
    end

    def get_port(spawn_new = true)
      add_worker if spawn_new && all_size == 0

      port = @workers_mutex.synchronize { @workers.shift }
      @workers_mutex.synchronize { @workers_in_use << port } if port

      Thread.new { check_min_free_workers } if spawn_new

      port
    end

    def check_min_free_workers
      if @check_mutex.try_lock
        # TODO: mutex, and dont do it if already in progress
        # do this in thread
        while all_size < config.min_free_workers
          unless config.spawn_parallel
            sleep 0.1 until @workers_mutex.synchronize { @spawning_workers.empty? }
          end
          add_worker
        end
        @check_mutex.unlock
      end
    end

    def all_size
      @workers_mutex.synchronize { @workers.size + @spawning_workers.size }
    end

    def stop!
      if spawning_worker_pids.include?(nil)
        puts "Waiting for workers to quit..."
        sleep 0.1 while spawning_worker_pids.include?(nil)
      end

      @workers_mutex.synchronize do
        (@spawning_workers + @workers_in_use + @workers).each do |port|
          kill_worker(port)
        end
      end
      exit(0)
    end
  private
    def kill_worker(port)
      print "- worker #{port}"
      worker_pid = @worker_pids[port]
      worker_pid ||= DRbObject.new_with_uri("druby://localhost:#{port}").pid
      system("kill -9 #{worker_pid} > /dev/null 2>&1")
      session_name = worker_session_name(port)
      system("screen -S #{session_name} -X quit > /dev/null 2>&1")
      puts "."
    rescue
    end

    def spawning_worker_pids
      @spawning_workers.map { |port| @worker_pids[port] }
    end

    def run
      trap("INT") { stop! }
      trap("TERM") { stop! }
      system("screen -wipe > /dev/null 2>&1")

      DRb.start_service("druby://localhost:#{config.base_port}", self)
      check_min_free_workers
      DRb.thread.join
    end
  end
end

Theine::Server.new
