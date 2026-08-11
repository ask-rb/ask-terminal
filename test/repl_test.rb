# frozen_string_literal: true

require_relative "test_helper"

class ReplTest < Minitest::Test
  # A scriptable client double: records calls, answers requests, and can
  # inject notifications the way a real host would.
  class FakeClient
    attr_reader :calls

    def initialize
      @calls = []
      @responses = Hash.new { |h, k| h[k] = {} }
      @notifications = Queue.new
      @closed = false
    end

    def stub_response(method, result)
      @responses[method] = result
    end

    def push_notification(method, params)
      @notifications << { "method" => method, "params" => params }
    end

    def initialize!
      @calls << [:initialize!]
      { "server" => { "name" => "ask-app-server", "version" => "0.3.0" } }
    end

    def create_session(workspace_path: nil, mode: nil, model: nil)
      @calls << [:create_session, workspace_path, mode, model]
      { "session" => { "sessionId" => "sess_1" } }
    end

    def subscribe(session_id, after_seq: 0)
      @calls << [:subscribe, session_id, after_seq]
      {}
    end

    def send(session_id, content, expected_turn_id: nil)
      @calls << [:send, session_id, content]
      @responses["session/send"]
    end

    def approve(session_id, interaction_id)
      @calls << [:approve, session_id, interaction_id]
      { "approved" => true }
    end

    def reject(session_id, interaction_id)
      @calls << [:reject, session_id, interaction_id]
      { "rejected" => true }
    end

    def approve_all(session_id)
      @calls << [:approve_all, session_id]
      { "approved" => 1 }
    end

    def reject_all(session_id)
      @calls << [:reject_all, session_id]
      { "rejected" => 1 }
    end

    def plan_approve(session_id)
      @calls << [:plan_approve, session_id]
      { "approved" => true }
    end

    def plan_reject(session_id)
      @calls << [:plan_reject, session_id]
      { "rejected" => true }
    end

    def abort(session_id)
      @calls << [:abort, session_id]
      { "aborted" => true }
    end

    def read_workspace_state(session_id = nil)
      @calls << [:read_workspace_state, session_id]
      { "workspace" => { "path" => "/tmp", "mode" => "require" } }
    end

    def list_interactions(session_id)
      @calls << [:list_interactions, session_id]
      { "interactions" => [] }
    end

    def request(method, params = {})
      @calls << [:request, method, params]
      @responses[method] || {}
    end

    def wait_notification(timeout: nil)
      @notifications.pop
    end
  end

  def setup
    @client = FakeClient.new
    @input = StringIO.new
    @output = StringIO.new
    @repl = Ask::Terminal::Repl.new(
      client: @client, input: @input, output: @output,
      workspace: "/tmp", approval: "on_request"
    )
  end

  def event(type, payload)
    Ask::SessionProtocol::Events.event(type: type, seq: 1, payload: payload).to_h
  end

  # ── Startup ────────────────────────────────────────────────────────────

  def test_run_creates_and_subscribes_a_session
    @input.string = "/exit\n"
    @repl.run

    assert_equal :initialize!, @client.calls[0][0]
    assert_equal [:create_session, "/tmp", "on_request", nil], @client.calls[1]
    assert_equal [:subscribe, "sess_1", 0], @client.calls[2]
  end

  # ── Prompt flow ────────────────────────────────────────────────────────

  def test_prompt_sends_and_waits_for_turn_end
    @client.stub_response("session/send", { "accepted" => true, "status" => "steered" })
    @input.string = "fix the bug\n/exit\n"

    # The turn completes immediately after the prompt is sent.
    completed = event("turn.completed", { "turnId" => "t1" })
    turn = Thread.new do
      sleep 0.05
      @client.push_notification("session/event", { "event" => completed })
    end

    @repl.run
    turn.join

    assert @client.calls.include?([:send, "sess_1", "fix the bug"])
    assert_includes @output.string, "turn completed"
  end

  # ── Approvals ──────────────────────────────────────────────────────────

  def test_approval_required_asks_and_resolves_on_yes
    @client.stub_response("session/send", { "accepted" => true, "status" => "steered" })
    @input.string = "run tests\n"        # the prompt
    @input.rewind
    @input.string += "y\n"               # the approval answer
    @input.string += "/exit\n"

    events = [
      event("approval.required", { "id" => "act_1", "toolName" => "bash", "args" => {} }),
      event("approval.updated", { "id" => "act_1", "status" => "approved" }),
      event("turn.completed", { "turnId" => "t1" })
    ]
    pusher = Thread.new do
      events.each do |ev|
        sleep 0.03
        @client.push_notification("session/event", { "event" => ev })
      end
    end

    @repl.run
    pusher.join

    assert @client.calls.include?([:approve, "sess_1", "act_1"]),
           "yes should approve the pending interaction"
    assert_includes @output.string, "requires approval"
  end

  def test_approval_required_rejects_on_no
    @client.stub_response("session/send", { "accepted" => true, "status" => "steered" })
    @input.string = "run tests\n"
    @input.rewind
    @input.string += "\n"                # default = no
    @input.string += "/exit\n"

    events = [
      event("approval.required", { "id" => "act_1", "toolName" => "write", "args" => {} }),
      event("approval.updated", { "id" => "act_1", "status" => "rejected" }),
      event("turn.completed", { "turnId" => "t1" })
    ]
    pusher = Thread.new do
      events.each do |ev|
        sleep 0.03
        @client.push_notification("session/event", { "event" => ev })
      end
    end

    @repl.run
    pusher.join

    assert @client.calls.include?([:reject, "sess_1", "act_1"])
  end

  # ── Plan ───────────────────────────────────────────────────────────────

  def test_plan_proposed_asks_and_approves
    @client.stub_response("session/send", { "accepted" => true, "status" => "steered" })
    @input.string = "plan this\n"
    @input.rewind
    @input.string += "y\n"
    @input.string += "/exit\n"

    events = [
      event("plan.proposed", { "id" => "plan_1", "plan" => "Step 1" }),
      event("plan.approved", { "plan" => "Step 1" }),
      event("turn.completed", { "turnId" => "t1" })
    ]
    pusher = Thread.new do
      events.each do |ev|
        sleep 0.03
        @client.push_notification("session/event", { "event" => ev })
      end
    end

    @repl.run
    pusher.join

    assert @client.calls.include?([:plan_approve, "sess_1"])
  end

  # ── Commands ───────────────────────────────────────────────────────────

  def test_approve_command_without_id_approves_all
    @input.string = "/approve\n/exit\n"
    @repl.run
    assert @client.calls.include?([:approve_all, "sess_1"])
  end

  def test_approve_command_with_id
    @input.string = "/approve act_3\n/exit\n"
    @repl.run
    assert @client.calls.include?([:approve, "sess_1", "act_3"])
  end

  def test_status_command_lists_workspace
    @input.string = "/status\n/exit\n"
    @repl.run
    assert @client.calls.include?([:read_workspace_state, "sess_1"])
    assert_includes @output.string, "/tmp"
  end

  def test_unknown_command_hints_help
    @input.string = "/bogus\n/exit\n"
    @repl.run
    assert_includes @output.string, "unknown command"
    assert_includes @output.string, "/help"
  end
end
