# frozen_string_literal: true

module Ask
  module Terminal
    # How the terminal client reaches a session host.
    #
    #   spawn   — launch ask-app-server as a subprocess (stdio transport);
    #             the "embedded" mode: one host process owned by this client
    #   connect — attach to an already-running host over its unix socket
    #             (multi-client mode: web console, bots, and this terminal
    #             share the same live sessions)
    module Host
      # A spawned host subprocess.
      SpawnResult = Data.define(:client, :stderr, :process) do
        # Close the client and reap the subprocess.
        def close
          client.close
          stderr.close rescue nil
          process&.wait rescue nil
        end
      end

      # Spawn ask-app-server as a subprocess and return a Client over its
      # stdio.
      #
      # @param command [String, nil] host command (defaults to the
      #   ask-app-server gem's executable, falling back to PATH)
      # @return [SpawnResult]
      def self.spawn(command: nil, args: [])
        require "open3"
        command ||= begin
          Gem.bin_path("ask-app-server", "ask-app-server")
        rescue Gem::Exception
          "ask-app-server"
        end

        stdin, stdout, stderr, wait_thread = Open3.popen3(command, *args)
        client = Client.new(input: stdout, output: stdin)
        SpawnResult.new(client: client, stderr: stderr, process: wait_thread)
      end

      # Attach to an existing host over its unix socket.
      #
      # @param socket_path [String] host socket (see Ask::AppServer::SocketServer)
      # @return [Client]
      def self.connect(socket_path)
        require "socket"
        socket = UNIXSocket.new(socket_path)
        Client.new(input: socket, output: socket)
      end
    end
  end
end
