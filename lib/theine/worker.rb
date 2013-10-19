root_path = ARGV[2]
APP_PATH = "#{root_path}/config/application"
require "#{root_path}/config/boot"
require "#{root_path}/config/environment"
require 'drb/drb'

module Theine
  class Worker
    attr_reader :command_proc

    def initialize
      @pumps = []
      @command_proc = proc { }
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

def exit_prompt
  print "\n"
  puts "Press Enter to finish."
  $stdin.gets
end

base_port = ARGV[0]
worker_port = ARGV[1]

worker = Theine::Worker.new
DRb.start_service("druby://localhost:#{worker_port}", worker)

balancer = DRbObject.new_with_uri("druby://localhost:#{base_port}")
balancer.worker_boot(worker_port)

begin
  DRb.thread.join
  worker.command_proc.call
ensure
  #exit_prompt
  balancer.worker_done(worker_port)
end
