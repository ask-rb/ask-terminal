# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  # A scripted NDJSON peer: reads requests from a pipe, writes canned
  # responses/notifications back. Lets tests drive the client's protocol
  # behavior without a real host.
  class FakeHost
    def initialize(script: {})
      @script = script  # method name => handler proc (request params) => response hash
      @reader, @writer = IO.pipe
      @client_input, @client_output = IO.pipe
      @thread = Thread.new { run }
    end

    attr_reader :reader, :writer, :client_input, :client_output

    def run
      @reader.each_line do |line|
        msg = JSON.parse(line)
        handler = @script[msg["method"]]
        if handler
          @client_output.puts(JSON.generate({ id: msg["id"], result: handler.call(msg["params"]) }))
        else
          @client_output.puts(JSON.generate({ id: msg["id"], error: { code: -32601, message: "no script" } }))
        end
        @client_output.flush
      end
    rescue IOError
      # client closed
    end

    def push_notification(method, params)
      @client_output.puts(JSON.generate({ method: method, params: params }))
      @client_output.flush
    end

    def close
      @reader.close rescue nil
      @client_output.close rescue nil
      @thread&.kill
    end
  end

  def setup
    @host = FakeHost.new(script: {
      "initialize" => ->(params) { { protocolVersion: "1.0", capabilities: [], server: { name: "fake", version: "0" } } },
      "ping" => ->(params) { { status: "ok" } },
      "session/create" => ->(params) { { session: { sessionId: "sess_1", model: "m", createdAt: Time.now.iso8601 } } },
      "session/send" => ->(params) { { accepted: true, status: "steered", turnId: "turn_1" } }
    })
    @client = Ask::Terminal::Client.new(input: @host.client_input, output: @host.writer)
  end

  def teardown
    @client.close
    @host.close
  end

  def test_request_gets_matching_response
    result = @client.request("ping")
    assert_equal({ "status" => "ok" }, result)
  end

  def test_convenience_wrappers
    init = @client.initialize!
    assert_equal "fake", init.dig("server", "name")

    created = @client.create_session(workspace_path: "/tmp", mode: "on_request")
    assert_equal "sess_1", created.dig("session", "sessionId")

    sent = @client.send("sess_1", "Hello")
    assert_equal "steered", sent["status"]

    assert_equal "ok", @client.request("ping")["status"]
  end

  def test_error_response_raises_protocol_error
    error = assert_raises(Ask::Terminal::Client::ProtocolError) do
      @client.request("session/close", { sessionId: "nope" })
    end
    assert_equal(-32601, error.code)
    assert_match(/no script/, error.message)
  end

  def test_notifications_are_queued
    @host.push_notification("session/event", { event: { type: "turn.started", seq: 1, payload: {} } })

    notification = @client.wait_notification(timeout: 1)
    assert_equal "session/event", notification["method"]
    assert_equal "turn.started", notification.dig("params", "event", "type")
  end

  def test_wait_notification_timeout_returns_nil
    assert_nil @client.wait_notification(timeout: 0.05)
  end

  def test_notifications_do_not_interleave_with_responses
    # Notification arrives before the request's response: the reader must
    # route the response to the pending request and queue the notification.
    @host.push_notification("session/event", { event: { type: "error", seq: 1, payload: { "error" => "x" } } })
    result = @client.request("ping")
    assert_equal({ "status" => "ok" }, result)

    notification = @client.wait_notification(timeout: 1)
    assert_equal "session/event", notification["method"]
  end

  def test_connection_closed_unblocks_waiters
    @host.close
    notification = @client.wait_notification(timeout: 2)
    assert_equal Ask::Terminal::Client::CONNECTION_CLOSED, notification
    assert @client.closed?
  end

  def test_connection_closed_raises_on_request
    @host.close
    assert_raises(Ask::Terminal::Client::ConnectionClosed) do
      @client.request("ping")
    end
  end
end
