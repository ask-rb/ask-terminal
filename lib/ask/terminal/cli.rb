# frozen_string_literal: true

require "optparse"

module Ask
  module Terminal
    # Command-line entry for the terminal client. Installed as `ask`
    # (primary) and `ask-terminal` (long alias).
    #
    #   ask                       spawn the host over stdio and attach
    #   ask --socket PATH         attach to a running host
    #   ask -w DIR --model M      options for session/create
    class CLI
      # The short command name (used in banners and help).
      COMMAND_NAME = "ask"

      def self.run!(args = ARGV)
        new(args).run
      end

      def initialize(args)
        @args = args.dup
      end

      def run
        options = {
          host: "stdio",
          socket: nil,
          workspace: Dir.pwd,
          model: nil,
          approval: "on_request"
        }

        parser = OptionParser.new do |o|
          o.banner = "Usage: #{COMMAND_NAME} [options]"
          o.on("--host MODE", "stdio (spawn the host) or socket (attach) [stdio]") { |v| options[:host] = v }
          o.on("--socket PATH", "Attach to a running host at PATH (implies --host socket)") { |v| options[:socket] = v }
          o.on("-w", "--workspace DIR", "Workspace directory [current dir]") { |v| options[:workspace] = v }
          o.on("--model MODEL", "Model identifier") { |v| options[:model] = v }
          o.on("--approval MODE", "Approval mode: on_request | off | auto [on_request]") { |v| options[:approval] = v }
          o.on("-h", "--help", "Show help") { puts o; return 0 }
        end
        parser.parse!(@args)

        client =
          if options[:socket] || options[:host] == "socket"
            socket_path = options[:socket] || ENV["ASK_APP_SERVER_SOCKET"]
            abort "a socket path is required (--socket PATH or ASK_APP_SERVER_SOCKET)" unless socket_path
            Host.connect(socket_path)
          else
            spawned = Host.spawn
            if spawned.socket_path
              puts "host socket: #{spawned.socket_path}"
              puts "attach with: ask --socket #{spawned.socket_path}"
            end
            spawned.client
          end

        repl = Repl.new(
          client: client,
          workspace: options[:workspace],
          model: options[:model],
          approval: options[:approval]
        )
        begin
          repl.run
        ensure
          client.close
        end
        0
      end
    end
  end
end
