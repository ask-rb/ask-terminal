# frozen_string_literal: true

require_relative "test_helper"

class RendererTest < Minitest::Test
  def setup
    @io = StringIO.new
  end

  def event(type, payload = {})
    Ask::SessionProtocol::Events.event(type: type, seq: 1, payload: payload)
  end

  def render(event, io: @io)
    Ask::Terminal::Renderer.render(event, io: io)
    io.string
  end

  def test_model_streaming_prints_without_newline
    out = render(event("model.streaming", { "delta" => "Hello " }))
    assert_equal "Hello ", out
  end

  def test_model_thinking_is_dimmed
    out = render(event("model.thinking", { "delta" => "hmm" }))
    assert_includes out, "hmm"
    assert_includes out, Ask::Terminal::Renderer::DIM
  end

  def test_tool_use_shows_name_and_args
    out = render(event("tool.use", { "id" => "c1", "name" => "bash", "args" => { "command" => "ls" } }))
    assert_includes out, "› bash"
    assert_includes out, "ls"
  end

  def test_tool_result_prints_output_and_duration
    out = render(event("tool.result", {
      "id" => "c1", "name" => "bash", "output" => "hi\n", "isError" => false, "durationMs" => 42
    }))
    assert_includes out, "42ms"
    assert_includes out, "hi"
  end

  def test_tool_result_error_is_red
    out = render(event("tool.result", {
      "id" => "c1", "name" => "bash", "output" => "boom", "isError" => true, "durationMs" => 1
    }))
    assert_includes out, "failed"
    assert_includes out, Ask::Terminal::Renderer::RED
  end

  def test_approval_required_asks_for_resolution
    out = render(event("approval.required", {
      "id" => "act_1", "toolName" => "bash", "args" => { "command" => "rm" }, "message" => "danger"
    }))
    assert_includes out, "bash requires approval"
    assert_includes out, "act_1"
  end

  def test_plan_proposed_shows_plan
    out = render(event("plan.proposed", { "id" => "plan_1", "plan" => "Step 1\nStep 2" }))
    assert_includes out, "Plan proposal"
    assert_includes out, "Step 1"
  end

  def test_todos_updated_shows_progress
    out = render(event("todos.updated", {
      "todos" => [
        { "id" => "todo_1", "title" => "a", "status" => "completed" },
        { "id" => "todo_2", "title" => "b", "status" => "pending" }
      ]
    }))
    assert_includes out, "1/2 done"
  end

  def test_turn_completed_prints_separator
    out = render(event("turn.completed", { "turnId" => "t1", "response" => "done" }))
    assert_includes out, "turn completed"
  end

  def test_turn_failed_is_red
    out = render(event("turn.failed", { "turnId" => "t1", "error" => "boom" }))
    assert_includes out, "boom"
    assert_includes out, Ask::Terminal::Renderer::RED
  end

  def test_accepts_wire_hash_events
    hash = { "type" => "error", "seq" => 1, "payload" => { "error" => "oops" } }
    out = render(hash)
    assert_includes out, "oops"
  end

  def test_unknown_event_types_render_nothing
    assert_empty render({ "type" => "mystery.event", "seq" => 1, "payload" => {} })
  end
end
