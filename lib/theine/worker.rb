root_path = ARGV[2]
APP_PATH = "#{root_path}/config/application"
require "#{root_path}/config/boot"
require "#{root_path}/config/environment"
require 'drb/drb'

$real_stdout = $stdout
$real_stderr = $stderr

class PrailsServer
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
      input.method_missing(:method, :readline).arity
    rescue NameError
      0
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
    ::Rails.application.config.console = Pry

    Pry.config.input = stdin
    Pry.config.output = stdout

    require 'rails/commands'
    sleep 0.1 # allow Pumps to finish
    DRb.stop_service
  end

  def stdin=(value)
    @stdin = InputProxy.new(value)
    $stdin = @stdin
  end

  def stdout=(value)
    $orig_stdout = $stdout
    @stdout = value
    r, w = IO.pipe
    $stdout = w
    @pumps << Pump.new(r, @stdout)
  end

  def stderr=(value)
    $orig_stderr = $stderr
    @stderr = value
    r, w = IO.pipe
    $stderr = w
    @pumps << Pump.new(r, @stderr)
  end

  def pid
    ::Process.pid
  end

private
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

base_port = ARGV[0]
instance_port = ARGV[1]
DRb.start_service("druby://localhost:#{instance_port}", PrailsServer.new)

balancer = DRbObject.new_with_uri("druby://localhost:#{base_port}")
balancer.instance_boot(instance_port)

begin
  DRb.thread.join
ensure
  balancer.instance_done(instance_port)
end
