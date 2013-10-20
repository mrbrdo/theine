RAILS_ROOT_PATH = ARGV[2]
APP_PATH = "#{RAILS_ROOT_PATH}/config/application"
require 'drb/drb'

module Theine
  class Worker
    attr_reader :command_proc

    def initialize
      @pumps = []
      @command_proc = proc { }
    end

    def boot
      require "#{RAILS_ROOT_PATH}/config/boot"
      require "#{RAILS_ROOT_PATH}/config/environment"
    end

    def command_rails(argv)
      ARGV.clear
      ARGV.concat(argv)

      set_command do
        require 'rails/commands'
      end
    end

    def command_rake(argv)
      set_command do
        ::Rails.application.load_tasks
        argv.each do |task|
          ::Rake::Task[task].invoke
        end
      end
    end

    def command_rspec(argv)
      set_command do
        require 'rspec/core'
        ::RSpec::Core::Runner.run(argv, $stderr, $stdout)
      end
    end

    def pid
      ::Process.pid
    end

    def stop!
      exit(1)
    end
  private
    def set_command(&block)
      rails_reload!
      @command_proc = block
      DRb.stop_service
    end

    def rails_reload!
      ActionDispatch::Reloader.cleanup!
      ActionDispatch::Reloader.prepare!
    end
  end
end

base_port = ARGV[0]
worker_port = ARGV[1].to_i

worker = Theine::Worker.new

balancer = DRbObject.new_with_uri("druby://localhost:#{base_port}")
balancer.set_worker_pid(worker_port, worker.pid)

worker.boot
DRb.start_service("druby://localhost:#{worker_port}", worker)
balancer.worker_boot(worker_port)

begin
  DRb.thread.join
  worker.command_proc.call
ensure
  balancer.worker_done(worker_port)
end
