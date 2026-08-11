# frozen_string_literal: true

require "json"

module Ask
  module Terminal
    # Renders canonical session events as ANSI terminal output. Accepts
    # either a wire hash ({ "type" =>, "seq" =>, "payload" => }) or an
    # Ask::SessionProtocol::Events::Event.
    module Renderer
      # ANSI helpers.
      DIM = "\e[2m"
      CYAN = "\e[36m"
      YELLOW = "\e[33m"
      GREEN = "\e[32m"
      RED = "\e[31m"
      MAGENTA = "\e[35m"
      RESET = "\e[0m"

      # How many lines of tool output to show inline.
      MAX_OUTPUT_LINES = 20
      MAX_ARG_CHARS = 120

      # Render one event to `io`. Streaming deltas (model.streaming,
      # tool.delta) print without a trailing newline; everything else
      # prints a complete line.
      #
      # @param event [Hash, Ask::SessionProtocol::Events::Event]
      # @param io [IO] output sink
      def self.render(event, io: $stdout)
        hash = event.respond_to?(:to_h) ? event.to_h : event
        payload = hash["payload"] || {}

        case hash["type"]
        when "model.streaming"
          io.print payload["delta"].to_s
        when "model.thinking"
          io.print "#{DIM}#{payload["delta"]}#{RESET}"
        when "tool.use"
          args = truncate(JSON.generate(payload["args"]))
          io.puts "\n#{CYAN}› #{payload["name"]}#{args.empty? ? "" : " #{args}"}#{RESET}"
        when "tool.delta"
          io.print payload["partial"].to_s
        when "tool.result"
          render_tool_result(payload, io)
        when "approval.required"
          io.puts "#{YELLOW}✋ #{payload["toolName"]} requires approval (#{payload["id"]})#{RESET}"
          io.puts "#{DIM}#{payload["message"]}#{RESET}" if payload["message"]
        when "approval.updated"
          mark = payload["status"] == "approved" ? "#{GREEN}✓#{RESET}" : "#{RED}✗#{RESET}"
          io.puts "#{mark} #{payload["status"]} (#{payload["id"]})"
        when "plan.proposed"
          io.puts "\n#{MAGENTA}📋 Plan proposal (#{payload["id"]}):#{RESET}"
          io.puts payload["plan"].to_s
          io.puts "#{DIM}plan/approve or plan/reject to continue#{RESET}"
        when "plan.approved"
          io.puts "#{GREEN}✓ plan approved#{RESET}"
        when "plan.rejected"
          io.puts "#{RED}✗ plan rejected#{RESET}"
        when "todos.updated"
          render_todos(payload["todos"], io)
        when "turn.started"
          io.puts "#{DIM}── turn started ──#{RESET}"
        when "turn.completed"
          io.puts "\n#{DIM}── turn completed ──#{RESET}"
        when "turn.failed"
          io.puts "\n#{RED}✗ turn failed: #{payload["error"]}#{RESET}"
        when "turn.aborted"
          io.puts "\n#{DIM}── turn aborted ──#{RESET}"
        when "error"
          io.puts "#{RED}⚠ #{payload["error"]}#{RESET}"
        when "session.created"
          io.puts "#{DIM}session #{payload["sessionId"]} created#{RESET}"
        when "session.ended"
          io.puts "#{DIM}session #{payload["sessionId"]} ended (#{payload["reason"]})#{RESET}"
        end
        io.flush
      end

      def self.render_tool_result(payload, io)
        output = payload["output"].to_s
        if payload["isError"]
          io.puts "#{RED}✗ #{payload["name"]} failed:#{RESET}"
        else
          io.puts "#{DIM}└ #{payload["name"]} (#{payload["durationMs"]}ms)#{RESET}" if payload["durationMs"]
        end
        return if output.empty?

        lines = output.lines
        lines.first(MAX_OUTPUT_LINES).each { |l| io.puts "#{DIM}  #{l.chomp}#{RESET}" }
        io.puts "#{DIM}  … #{lines.size - MAX_OUTPUT_LINES} more lines#{RESET}" if lines.size > MAX_OUTPUT_LINES
      end

      def self.render_todos(todos, io)
        return unless todos.is_a?(Array) && !todos.empty?

        done = todos.count { |t| t["status"] == "completed" }
        io.puts "#{DIM}todos: #{done}/#{todos.size} done#{RESET}"
      end

      def self.truncate(string)
        string.to_s[0, MAX_ARG_CHARS]
      end
      private_class_method :truncate, :render_tool_result, :render_todos
    end
  end
end
