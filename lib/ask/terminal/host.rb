# frozen_string_literal: true

require "securerandom"

module Ask
  module Terminal
    # How the terminal client reaches a session host.
    #
    #   spawn   — launch ask-app-server as a subprocess (stdio transport)
    #             with a unix socket for multi-client attach; the
    #             "embedded" mode: one host process owned by this client
    #   connect — attach to an already-running host over its unix socket
    #             (multi-client mode: web console, bots, and this terminal
    #             share the same live sessions)
    module Host
      # A spawned host subprocess.
      SpawnResult = Data.define(:client, :stderr, :process, :socket_path) do
        # Close the client and reap the subprocess.
        def close
          client.close
          stderr.close rescue nil
          process&.wait rescue nil
        end
      end

      # Spawn ask-app-server as a subprocess and return a Client over its
      # stdio. By default the host also exposes a unix socket (unique per
      # spawn under ~/.ask-app-server/sockets/) so other clients — the web
      # console, bots, a second terminal — can attach to the same live
      # sessions; the path is available on the result.
      #
      # @param command [String, nil] host command (defaults to the
      #   ask-app-server gem's executable, falling back to PATH)
      # @param args [Array<String>] extra host arguments
      # @param socket [Boolean, String, nil] true (default) spawns with a
      #   generated unique socket; a String uses that exact path; false
      #   disables the socket entirely
      # @return [SpawnResult]
      def self.spawn(command: nil, args: [], socket: true)
        require "open3"
        command ||= begin
          Gem.bin_path("ask-app-server", "ask-app-server")
        rescue Gem::Exception
          "ask-app-server"
        end

        socket_path = resolve_socket_path(socket)
        spawn_args = args.dup
        spawn_args += ["--socket", socket_path] if socket_path

        stdin, stdout, stderr, wait_thread = Open3.popen3(command, *spawn_args)
        client = Client.new(input: stdout, output: stdin)
        SpawnResult.new(client: client, stderr: stderr, process: wait_thread, socket_path: socket_path)
      end

      # Attach to an existing host over its unix socket.
      #
      # @param socket_path [String] host socket (printed by `ask` on spawn)
      # @return [Client]
      def self.connect(socket_path)
        require "socket"
        socket = UNIXSocket.new(socket_path)
        Client.new(input: socket, output: socket)
      end

      # @api private
      def self.resolve_socket_path(socket)
        return nil if socket == false || socket.nil?
        return socket if socket.is_a?(String)

        # Explicit env wins; otherwise a unique path per spawn so
        # concurrent hosts never fight over the same socket.
        ENV["ASK_APP_SERVER_SOCKET"] ||
          File.join(Dir.home, ".ask-app-server", "sockets", "#{SecureRandom.hex(8)}.sock")
      end
      private_class_method :resolve_socket_path
    end
  end
end
