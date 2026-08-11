# frozen_string_literal: true

module Ask
  module Terminal
    # The interactive terminal coding agent: a thin client of the session
    # protocol. Owns one session with the host and drives it entirely
    # through canonical requests and events:
    #
    #   prompt → session/send → stream events → turn ends → prompt again
    #
    # Human-in-the-loop events are handled inline: approvals ask y/n,
    # plan proposals ask approve/reject, and both resolve through the
    # canonical interaction/plan methods — the same requests any other
    # client (web console, bot) would make.
    class Repl
      # @param client [Client] protocol client (spawned host or socket)
      # @param input [IO] user input (readline when a tty, else gets)
      # @param output [IO] rendered output
      # @param workspace [String] workspace path for session/create
      # @param model [String, nil] model override
      # @param approval [String] approval mode: on_request | off | auto
      def initialize(client:, input: $stdin, output: $stdout, workspace: Dir.pwd,
                     model: nil, approval: "on_request")
        @client = client
        @input = input
        @output = output
        @workspace = workspace
        @model = model
        @approval = approval
        @session_id = nil
        @turn_active = false
      end

      # Connect to the host, create a session, and run the interactive loop.
      # Returns when the user exits (/exit or EOF).
      def run
        handshake = @client.initialize!
        @server_info = handshake["server"] || {}

        created = @client.create_session(
          workspace_path: @workspace, mode: @approval, model: @model
        )
        @session_id = created.dig("session", "sessionId")
        @client.subscribe(@session_id, after_seq: 0)

        banner
        main_loop
      rescue Client::ConnectionClosed
        @output.puts "\n#{Renderer::RED}host closed the connection#{Renderer::RESET}"
      end

      private

      def banner
        @output.puts "#{Renderer::DIM}ask-terminal #{Ask::Terminal::VERSION} · " \
                     "protocol #{Ask::SessionProtocol::PROTOCOL_VERSION} · " \
                     "host #{@server_info["name"]} #{@server_info["version"]}#{Renderer::RESET}"
        @output.puts "#{Renderer::DIM}workspace: #{@workspace} · session: #{@session_id}#{Renderer::RESET}"
        @output.puts "#{Renderer::DIM}type /help for commands#{Renderer::RESET}"
      end

      def main_loop
        loop do
          line = prompt
          break if line.nil?

          line = line.strip
          next if line.empty?

          if line.start_with?("/")
            break if handle_command(line)
          else
            send_prompt(line)
          end
        end
      end

      def prompt
        if @input.respond_to?(:tty?) && @input.tty?
          require "readline"
          Readline.readline("ask> ")
        else
          @output.print "ask> "
          @output.flush
          @input.gets
        end
      end

      def send_prompt(content)
        result = @client.send(@session_id, content)
        case result["status"]
        when "stale"
          @output.puts "#{Renderer::YELLOW}message not accepted: turn moved on (stale)#{Renderer::RESET}"
        when "queued"
          @output.puts "#{Renderer::DIM}queued for the next turn boundary#{Renderer::RESET}"
        end
        wait_for_turn_end
      end

      # Drain notifications until the current turn ends. Approval and plan
      # interactions are resolved inline; Ctrl-C aborts the turn.
      def wait_for_turn_end
        @turn_active = true
        loop do
          notification = @client.wait_notification(timeout: 0.2)
          if notification.nil?
            # No traffic this tick; keep waiting unless the turn already
            # ended via an earlier event.
            return unless @turn_active
            next
          end
          return if notification == Client::CONNECTION_CLOSED

          event = notification["params"] && notification["params"]["event"]
          next unless event

          Renderer.render(event, io: @output)
          payload = event["payload"] || {}
          case event["type"]
          when "turn.completed", "turn.failed", "turn.aborted"
            @turn_active = false
            return
          when "approval.required"
            resolve_approval(payload)
          when "plan.proposed"
            resolve_plan(payload)
          end
        end
      rescue Interrupt
        @output.puts "\n#{Renderer::DIM}aborting turn…#{Renderer::RESET}"
        @client.abort(@session_id) rescue nil
        retry
      ensure
        @turn_active = false
      end

      def resolve_approval(payload)
        @output.print "Approve #{payload["toolName"]} (#{payload["id"]})? [y/N] "
        @output.flush
        answer = @input.gets
        if answer&.strip&.match?(/\Ay(es)?\z/i)
          @client.approve(@session_id, payload["id"])
        else
          @client.reject(@session_id, payload["id"])
        end
      end

      def resolve_plan(payload)
        @output.print "Approve plan? [y/N] "
        @output.flush
        answer = @input.gets
        if answer&.strip&.match?(/\Ay(es)?\z/i)
          @client.plan_approve(@session_id)
        else
          @client.plan_reject(@session_id)
        end
      end

      # ── Commands ────────────────────────────────────────────────────────

      # @return [Boolean] true when the repl should exit
      def handle_command(line)
        command, *args = line.split(/\s+/)
        case command
        when "/exit", "/quit"
          true
        when "/help"
          print_help
        when "/approve"
          args.empty? ? @client.approve_all(@session_id) : @client.approve(@session_id, args[0])
          @output.puts "#{Renderer::GREEN}✓ approved#{Renderer::RESET}"
        when "/reject"
          args.empty? ? @client.reject_all(@session_id) : @client.reject(@session_id, args[0])
          @output.puts "#{Renderer::RED}✗ rejected#{Renderer::RESET}"
        when "/plan-approve"
          @client.plan_approve(@session_id)
        when "/plan-reject"
          @client.plan_reject(@session_id)
        when "/abort"
          @client.abort(@session_id)
          @output.puts "#{Renderer::DIM}abort sent#{Renderer::RESET}"
        when "/status"
          print_status
        when "/sessions"
          list = @client.request("session/list", {})
          (list["sessions"] || []).each do |s|
            @output.puts "#{s["sessionId"]}  #{s["model"]}  #{s["running"] ? "running" : "idle"}"
          end
        else
          @output.puts "#{Renderer::YELLOW}unknown command: #{command} (try /help)#{Renderer::RESET}"
        end
        false
      end

      def print_help
        @output.puts <<~HELP
          #{Renderer::DIM}commands:#{Renderer::RESET}
            /approve [id]      approve a pending approval (all when no id)
            /reject [id]       reject a pending approval (all when no id)
            /plan-approve      approve the pending plan proposal
            /plan-reject       reject the pending plan proposal
            /abort             abort the running turn
            /status            show workspace and pending interactions
            /sessions          list host sessions
            /exit              quit
        HELP
      end

      def print_status
        state = @client.read_workspace_state(@session_id)
        workspace = state["workspace"] || {}
        @output.puts "#{Renderer::DIM}workspace: #{workspace["path"] || "—"} · " \
                     "mode: #{workspace["mode"]}#{Renderer::RESET}"

        interactions = @client.list_interactions(@session_id)
        pending = interactions["interactions"] || []
        if pending.empty?
          @output.puts "#{Renderer::DIM}no pending approvals#{Renderer::RESET}"
        else
          pending.each do |i|
            @output.puts "#{Renderer::YELLOW}✋ #{i["payload"]["toolName"]} (#{i["id"]})#{Renderer::RESET}"
          end
        end
      end
    end
  end
end
