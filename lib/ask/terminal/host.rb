# frozen_string_literal: true

# Host spawning/attach moved to the ask-session-client gem; this constant
# is kept as an alias so existing references keep working.
require "ask-session-client"

Ask::Terminal::Host = Ask::SessionClient::Host
