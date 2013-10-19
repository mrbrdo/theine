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
      exec("screen -r theine#{@port}")
    end

    def run_command
      case @argv[0]
      when "rake"
        @argv.shift
        @worker.command_rake(@argv)
      when "rspec"
        @argv.shift
        @worker.command_rspec(@argv)
      else
        @worker.command_rails(@argv)
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
