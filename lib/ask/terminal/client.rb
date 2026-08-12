# frozen_string_literal: true

# The protocol client lives in ask-session-protocol; this constant is
# kept as an alias so existing references keep working.
require "ask-session-protocol"

Ask::Terminal::Client = Ask::SessionProtocol::Client
