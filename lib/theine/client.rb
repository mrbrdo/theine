require 'drb/drb'
require 'readline'
require_relative './config'

module Theine
  class Client
    def self.start
      new
    end

    attr_reader :config

    def initialize
      @config = ConfigReader.new(Dir.pwd)
      @argv = ARGV.dup
      begin
        connect_worker
        run_command
        attach_screen
        exit_prompt
      end
    end

  private
    def attach_screen
      # Using vt100 because it does not have smcup/rmcup support,
      # which means the output of the screen will stay shown after
      # screen closes.
      set_vt_100 = "export TERM=vt100; tset"
      erase_screen_message = "echo '\\033[2A\\033[K'"
      exec("#{set_vt_100}; screen -r theine#{@port}; #{erase_screen_message}")
    end

    def run_command
      argv = @argv.dup
      command = argv.shift

      case command
      when "rake"
        @worker.command_rake(argv)
      when "rspec"
        @worker.command_rspec(argv)
      else
        @worker.command_rails([command] + argv)
      end
    rescue DRb::DRbConnError
      $stderr.puts "\nTheine closed the connection."
    end

    def connect_worker
      balancer = wait_until_result("Cannot connect to theine server. Waiting") do
        object = DRbObject.new_with_uri("druby://localhost:#{config.base_port}")
        object.respond_to?(:get_port) # test if connected
        object
      end
      @port = wait_until_result("Waiting for Theine worker...") do
        balancer.get_port
      end
      @worker = DRbObject.new_with_uri("druby://localhost:#{@port}")
    end

    WaitResultNoResultError = Class.new(StandardError)
    def wait_until_result(wait_message)
      result = nil
      dots = 0
      begin
        result = yield
        raise WaitResultNoResultError unless result
      rescue DRb::DRbConnError, WaitResultNoResultError
        print dots == 0 ? wait_message : "."
        dots += 1
        sleep 0.5
        retry
      end
      print "\n" if dots > 0
      result
    end
  end
end

DRb.start_service
Theine::Client.start
