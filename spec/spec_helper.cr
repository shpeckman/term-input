# spec/spec_helper.cr
require "spec"
require "wait_group"
require "../src/term-input"

def report(input, expected, actual) : Nil
  puts "\n[TEST] Input:    #{input.inspect}"
  puts "[TEST] Expected: #{expected.inspect}"
  puts "[TEST] Actual:   #{actual.inspect}"
end

class EventProbe
  getter events   : Array(Term::Input::Event)           = [] of Term::Input::Event
  getter keys     : Array(Term::Input::Keyboard::Event) = [] of Term::Input::Keyboard::Event
  getter mice     : Array(Term::Input::Mouse::Event)    = [] of Term::Input::Mouse::Event
  getter windows  : Array(Term::Input::Window::Event)   = [] of Term::Input::Window::Event
  getter unknowns : Array(Term::Input::Unknown::Event)  = [] of Term::Input::Unknown::Event
  getter pastes   : Array(String)                       = [] of String

  getter filter : Term::Mux::InputFilter
  getter input  : Term::Input::Events

  def initialize(drag_threshold : Int32      = Term::Input::Events::DEFAULT_DRAG_THRESHOLD,
                 click_interval : Time::Span = Term::Input::Events::DEFAULT_CLICK_INTERVAL,
                 click_slop     : Int32      = Term::Input::Events::DEFAULT_CLICK_SLOP,
                 escape_ticks   : Int32      = 2)
    @filter = Term::Mux::InputFilter.new(escape_ticks)
    @input  = Term::Input::Events.new(@filter, drag_threshold, click_interval, click_slop)

    @input.on_event { |event| @events << event }
    @input.on_key { |event| @keys << event }
    @input.on_mouse { |event| @mice << event }
    @input.on_window { |event| @windows << event }
    @input.on_unknown { |event| @unknowns << event }
    @input.on_paste { |content| @pastes << content }
  end

  def feed(bytes : Bytes) : String
    String.new(@filter.feed(bytes))
  end

  def feed(text : String) : String
    feed(text.to_slice)
  end

  def tick : String
    String.new(@filter.tick)
  end

  def cell : Term::Input::CellSize?
    @input.cell
  end

  def names : Array(String)
    event_names(@events)
  end
end

def probe(**options, &) : EventProbe
  probe = EventProbe.new(**options)
  yield probe
  probe
end

def parse_events(input : String, cell : Term::Input::CellSize? = nil) : Array(Term::Input::Event)
  p = EventProbe.new
  seed_cell(p, cell)
  p.feed(input)
  p.events
end

def parse_result(input : String, cell : Term::Input::CellSize? = nil) : {Bool, Array(Term::Input::Event)}
  events = parse_events(input, cell)
  known  = events.reject(&.is_a?(Term::Input::Unknown::Event))
  {known.size > 0 && events.size == known.size, known}
end

def parse_one(input : String, cell : Term::Input::CellSize? = nil) : Term::Input::Event
  events = parse_events(input, cell)
  events.size.should eq 1
  events.first
end

def emitted?(input : String, cell : Term::Input::CellSize? = nil) : Bool
  !parse_events(input, cell).empty?
end

def seed_cell(probe : EventProbe, cell : Term::Input::CellSize?) : Nil
  return unless cell
  probe.feed("\e[6;#{cell.h};#{cell.w}t")
  probe.events.clear
  probe.windows.clear
end

def collect_events(inputs : Array(String), **options) : Array(Term::Input::Event)
  p = EventProbe.new(**options)
  inputs.each { |input| p.feed(input) }
  p.events
end

def event_names(events : Array(Term::Input::Event)) : Array(String)
  events.map { |event| event.class.name.sub("Term::Input::", "") }
end

def bytes_to_s(bytes : Bytes) : String
  String.new(bytes)
end
