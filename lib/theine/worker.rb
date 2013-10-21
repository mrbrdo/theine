RAILS_ROOT_PATH = ARGV[2]
APP_PATH = "#{RAILS_ROOT_PATH}/config/application"
require 'drb/drb'

module Theine
  class Worker
    attr_reader :port, :balancer

    COMMANDS = {
      rails: proc {
        require 'rails/commands'
      },
      rake: proc {
        ::Rails.application.load_tasks
        ARGV.each do |task|
          ::Rake::Task[task].invoke
        end
      },
      rspec: proc {
        require 'rspec/core'
        RSpec::Core::Runner.autorun
      }
    }

    def initialize(port, balancer)
      @port = port
      @balancer = balancer
      @command_proc = proc { }
    end

    def run
      boot
      begin
        DRb.thread.join
        screen_move_to_bottom
        sleep 0.1 while !screen_attached?

        puts "command: #{@command_name} #{argv_to_s}"
        @command_proc.call
      ensure
        balancer.worker_done(port)
      end
    end

    COMMANDS.each_pair do |command_name, command|
      define_method("command_#{command_name}") do |argv|
        set_argv(argv)
        set_command(command_name, &command)
      end
    end

    def pid
      ::Process.pid
    end

    def stop!
      exit(1)
    end

    def screen_attached?
      !system("screen -ls | grep theine#{@port} | grep Detached > /dev/null")
    end

    def screen_move_to_bottom
      puts "\033[22B"
    end

  private
    def set_command(command_name, &block)
      rails_reload!
      @command_name = command_name
      @command_proc = block
      DRb.stop_service
    end

    def argv_to_s
      ARGV.map { |arg|
        if arg.include?(" ")
          "\"#{arg}\""
        else
          arg
        end
      }.join(' ')
    end

    def set_argv(argv)
      ARGV.clear
      ARGV.concat(argv)
    end

    def rails_reload!
      ActionDispatch::Reloader.cleanup!
      ActionDispatch::Reloader.prepare!
    end

    def start_service
      DRb.start_service("druby://localhost:#{@port}", self)
    end

    def boot
      balancer.set_worker_pid(port, pid)

      require "#{RAILS_ROOT_PATH}/config/boot"
      require "#{RAILS_ROOT_PATH}/config/environment"
      start_service

      balancer.worker_boot(port)
    end
  end
end

balancer = DRbObject.new_with_uri("druby://localhost:#{ARGV[0]}")
worker = Theine::Worker.new(ARGV[1].to_i, balancer)

worker.run
