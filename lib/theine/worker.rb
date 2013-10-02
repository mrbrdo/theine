root_path = ARGV[2]
APP_PATH = "#{root_path}/config/application"
require "#{root_path}/config/boot"
require "#{root_path}/config/environment"
require 'drb/drb'

$real_stdout = $stdout
$real_stderr = $stderr

module Theine
  class Worker
    attr_reader :stdin, :stdout, :stderr
    InputProxy = Struct.new :input do
      # Reads a line from the input
      def readline(prompt)
        case readline_arity
        when 1 then input.readline(prompt)
        else        input.readline
        end
      end

      def completion_proc=(val)
        input.completion_proc = val
      end

      def readline_arity
        input.readline_arity
      end

      def gets(*args)
        input.gets(*args)
      end
    end

    def initialize
      @pumps = []
    end

    def command_rails(argv)
      rails_reload!

      ARGV.clear
      ARGV.concat(argv)

      require 'pry'
      ::Rails.application.config.console = ::Pry
      pry_setup

      require 'rails/commands'
      sleep 0.1 # allow Pumps to finish
      DRb.stop_service
    end

    def command_rake(argv)
      pry_setup
      ::Rails.application.load_tasks
      argv.each do |task|
        ::Rake::Task[task].invoke
      end
    end

    def command_rspec(argv)
      pry_setup
      require 'rspec/core'
      ::RSpec::Core::Runner.run(argv, $stderr, $stdout)
    end

    def pry_setup
      ::Pry.config.input = stdin
      ::Pry.config.output = stdout
    end

    def stdin=(value)
      @stdin = InputProxy.new(value)
      $stdin = @stdin
    end

    def stdout=(value)
      patch_out_io($stdout, value)
      @stdout = value
      r, w = IO.pipe
      $stdout = w
      @pumps << Pump.new(r, @stdout)
    end

    def stderr=(value)
      patch_out_io($stderr, value)
      @stderr = value
      r, w = IO.pipe
      $stderr = w
      @pumps << Pump.new(r, @stderr)
    end

    def pid
      ::Process.pid
    end

  private
    def patch_out_io(io, write_to)
      # This is done because Rails 'remembers' $stdout in some places when it's
      # loaded, for example for logging SQL in the Rails console.
      # We have to pre-load Rails and at that point we do not know what to change
      # $stdout to, so this is why we patch it here.
      io.singleton_class.send :define_method, :write do |*args, &block|
        write_to.write(*args, &block)
      end
    end

    def rails_reload!
      ActionDispatch::Reloader.cleanup!
      ActionDispatch::Reloader.prepare!
    end

    class Pump < Thread
      def initialize(input, output)
        if output
          @input = input
          @output = output
          super(&method(:main))
        else
          close_stream(input)
        end
      end

    private
      def main
        while buf = @input.sysread(1024)
          @output.print(buf)
          @output.flush
        end
      ensure
        @output.close
      end
    end
  end
end

base_port = ARGV[0]
worker_port = ARGV[1]
DRb.start_service("druby://localhost:#{worker_port}", Theine::Worker.new)

balancer = DRbObject.new_with_uri("druby://localhost:#{base_port}")
balancer.worker_boot(worker_port)

begin
  DRb.thread.join
ensure
  balancer.worker_done(worker_port)
end
