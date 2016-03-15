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
        require 'rake'
        ::Rails.application.load_tasks if defined? ::Rails

        tasks = []
        ARGV.each do |arg|
          if arg =~ /^(\w+)=(.*)$/m
            ENV[$1] = $2
          else
            tasks << arg
          end
        end

        tasks.each do |task|
          is_test_task = task =~ /^(spec|test)$/
          if is_test_task
            previous_env = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
            change_rails_env_to("test")
          end

          ::Rake::Task[task].invoke

          change_rails_env_to(previous_env) if is_test_task
        end
      },
      rspec: proc {
        change_rails_env_to("test")

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
        instance_exec(&@command_proc)
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

    def change_rails_env_to(env)
      ENV['RAILS_ENV'] = env
      ENV['RACK_ENV'] = env
      if defined? ::Rails
        ::Rails.env = env

        # load config/environments/test.rb
        test_env_rb = ::Rails.root.join("config/environments/#{env}.rb")
        load(test_env_rb) if File.exist?(test_env_rb)

        if defined? ActiveRecord
          ActiveRecord::Base.establish_connection rescue nil
        end

        if defined? SequelRails
          Sequel::Model.db = SequelRails.setup env
        end
      end
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
