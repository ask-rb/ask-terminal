# frozen_string_literal: true

# Host spawning/attach lives in ask-session-protocol; this constant is
# kept as an alias so existing references keep working.
require "ask-session-protocol"

Ask::Terminal::Host = Ask::SessionProtocol::Host
