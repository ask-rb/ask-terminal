# frozen_string_literal: true

require "json"
require "timeout"
require "thread"

module Ask
  module Terminal
    # A thin client of the canonical Ask::SessionProtocol. Speaks NDJSON
    # over an input/output pair (the spawned host's stdio, or a unix
    # socket) and knows nothing else: no runtime, no sessions — the host
    # owns all of it.
    #
    # A reader thread routes incoming messages: responses are matched to
    # their pending request by id and delivered with a ConditionVariable;
    # everything else (session/event notifications, reverse requests) is
    # pushed to a notification queue for the caller to drain.
    class Client
      # Raised when a request gets no response in time.
      class RequestTimeout < StandardError; end

      # Raised when the host closes the connection.
      class ConnectionClosed < StandardError; end

      # A JSON-RPC error from the host.
      class ProtocolError < StandardError
        attr_reader :code

        def initialize(code, message)
          @code = code
          super(message)
        end
      end

      # Sentinel notification pushed when the host closes the connection,
      # so waiters on {#wait_notification} unblock.
      CONNECTION_CLOSED = { "method" => "connection.closed" }.freeze

      # @param input [IO] NDJSON source (host stdout / socket)
      # @param output [IO] NDJSON sink (host stdin / socket)
      def initialize(input:, output:)
        @input = input
        @output = output
        @pending = {}
        @next_id = 1
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @notifications = Queue.new
        @closed = false
        @reader = Thread.new { read_loop }
      end

      # Send a request and wait for its response.
      #
      # @param method [String] canonical client → host method
      # @param params [Hash]
      # @param timeout [Numeric, nil] seconds to wait; nil waits forever
      # @return [Hash] the response result
      # @raise [ProtocolError] on a JSON-RPC error response
      # @raise [RequestTimeout] when no response arrives in time
      # @raise [ConnectionClosed] when the host closed the connection
      def request(method, params = {}, timeout: nil)
        raise ConnectionClosed, "connection is closed" if @closed

        id = next_id
        entry = { done: false, result: nil, error: nil }
        @mutex.synchronize { @pending[id] = entry }

        @output.puts(JSON.generate({ id: id, method: method, params: params }))
        @output.flush

        deadline = timeout && (Time.now + timeout)
        @mutex.synchronize do
          until entry[:done]
            remaining = deadline && (deadline - Time.now)
            raise RequestTimeout, "#{method} timed out after #{timeout}s" if remaining && remaining <= 0

            @condition.wait(@mutex, remaining || 1)
          end
        end
        raise entry[:error] if entry[:error]

        entry[:result]
      ensure
        @mutex.synchronize { @pending.delete(id) } if id
      end

      # Wait for the next notification (blocking, or with a timeout).
      # Returns a Hash { "method" =>, "params" => }, or the
      # {CONNECTION_CLOSED} sentinel when the host disconnected.
      def wait_notification(timeout: nil)
        return @notifications.pop unless timeout

        Timeout.timeout(timeout) { @notifications.pop }
      rescue Timeout::Error
        nil
      end

      # True when the host connection has closed.
      def closed?
        @closed
      end

      # Close the client: close the sink (which ends the host's stdin,
      # for spawned hosts) and stop the reader thread.
      def close
        @output.close rescue nil
        @reader&.kill rescue nil
      end

      # ── Convenience wrappers over the canonical surface ────────────────

      def initialize!(client: { name: "ask-terminal", version: Ask::Terminal::VERSION })
        request("initialize", { client: client })
      end

      def create_session(workspace_path: nil, mode: nil, model: nil)
        request("session/create", {
          workspace: { workspacePath: workspace_path },
          mode: mode,
          model: model
        }.compact)
      end

      def subscribe(session_id, after_seq: 0)
        request("session/subscribe", { sessionId: session_id, afterSeq: after_seq })
      end

      def send(session_id, content, expected_turn_id: nil)
        params = { sessionId: session_id, content: content }
        params[:expectedTurnId] = expected_turn_id if expected_turn_id
        request("session/send", params)
      end

      def abort(session_id)
        request("session/abort", { sessionId: session_id })
      end

      def close_session(session_id)
        request("session/close", { sessionId: session_id })
      end

      def list_interactions(session_id)
        request("interaction/list", { sessionId: session_id })
      end

      def approve(session_id, interaction_id)
        request("interaction/approve", { sessionId: session_id, interactionId: interaction_id })
      end

      def reject(session_id, interaction_id)
        request("interaction/reject", { sessionId: session_id, interactionId: interaction_id })
      end

      def approve_all(session_id)
        request("interaction/approve-all", { sessionId: session_id })
      end

      def reject_all(session_id)
        request("interaction/reject-all", { sessionId: session_id })
      end

      def plan_approve(session_id)
        request("plan/approve", { sessionId: session_id })
      end

      def plan_reject(session_id)
        request("plan/reject", { sessionId: session_id })
      end

      def read_workspace_state(session_id = nil)
        params = session_id ? { sessionId: session_id } : {}
        request("workspace/readState", params)
      end

      private

      def next_id
        @mutex.synchronize do
          id = @next_id
          @next_id += 1
          id
        end
      end

      def read_loop
        while (line = @input.gets)
          line = line.strip
          next if line.empty?

          msg = JSON.parse(line)
          if response?(msg)
            deliver_response(msg)
          else
            @notifications << msg
          end
        end
      rescue JSON::ParserError, IOError, SystemCallError
        # Host went away or sent garbage; fall through to close handling.
      ensure
        mark_closed
      end

      def response?(msg)
        msg["id"] && !msg.key?("method")
      end

      def deliver_response(msg)
        entry = @mutex.synchronize { @pending.delete(msg["id"]) }
        return unless entry

        entry[:error] = build_error(msg["error"]) if msg["error"]
        entry[:result] = msg["result"] unless msg["error"]
        entry[:done] = true
        @mutex.synchronize { @condition.broadcast }
      end

      def build_error(error)
        ProtocolError.new(error["code"], error["message"].to_s)
      end

      def mark_closed
        @mutex.synchronize do
          @closed = true
          @pending.each_value do |entry|
            entry[:error] = ConnectionClosed.new("host closed the connection")
            entry[:done] = true
          end
          @pending.clear
          @condition.broadcast
        end
        @notifications << CONNECTION_CLOSED
      end
    end
  end
end
