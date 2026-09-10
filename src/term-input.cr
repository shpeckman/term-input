# src/term-input.cr
require "term-seq/filter"
require "./input/core"
require "./input/keyboard"
require "./input/mouse"
require "./input/window"
require "./input/unknown"
require "./input/events"

module Term::Input
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  ENABLE_INPUT  = "\e[?2004;1003;1016;1004;2048;2031;2033h\e[=31u"
  DISABLE_INPUT = "\e[=0u\e[?2004;1003;1016;1004;2048;2031;2033l"
end
