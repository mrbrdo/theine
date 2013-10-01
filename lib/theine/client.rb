require 'drb/drb'
require 'readline'

PRAILS_BASE_PORT = 11000

class IOUndumpedProxy
  include DRb::DRbUndumped

  def initialize(obj)
    @obj = obj
  end

  def completion_proc=(val)
    if @obj.respond_to? :completion_proc=
      @obj.completion_proc = val
    end
  end

  def completion_proc
    @obj.completion_proc if @obj.respond_to? :completion_proc
  end

  def readline(prompt)
    if ::Readline == @obj
      @obj.readline(prompt, true)
    elsif @obj.method(:readline).arity == 1
      @obj.readline(prompt)
    else
      $stdout.print prompt
      @obj.readline
    end
  end

  def puts(*lines)
    @obj.puts(*lines)
  end

  def print(*objs)
    @obj.print(*objs)
  end

  def write(data)
    @obj.write data
  end

  def <<(data)
    @obj << data
    self
  end

  def flush
    @obj.flush
  end

  # Some versions of Pry expect $stdout or its output objects to respond to
  # this message.
  def tty?
    false
  end
end

argv = ARGV.dup
ARGV.clear

DRb.start_service

i = 1
begin
  balancer = DRbObject.new_with_uri("druby://localhost:#{PRAILS_BASE_PORT}")
  sleep 0.1 until port = balancer.get_port
  prails = DRbObject.new_with_uri("druby://localhost:#{port}")
rescue DRb::DRbConnError
  sleep 0.5
  putc "."
  i += 1
  retry
end
putc "\n"

trap('INT') {
  %x[kill -2 #{prails.pid}]
}

prails.stdin = IOUndumpedProxy.new($stdin)
prails.stdout = IOUndumpedProxy.new($stdout)
prails.stderr = IOUndumpedProxy.new($stderr)
begin
  prails.command_rails(argv)
rescue DRb::DRbConnError
end
