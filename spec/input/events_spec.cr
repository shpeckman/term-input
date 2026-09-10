# spec/input/events_spec.cr
require "../spec_helper"

describe Term::Input::Events do
  describe "pass through" do
    it "forwards every sequence to the child unchanged" do
      input = "\e[97u\e[<0;10;20M\e[I"
      p     = EventProbe.new

      actual = p.feed(input)
      report(input, input, actual)
      actual.should eq input
    end

    it "forwards plain text untouched" do
      input = "hello"
      p     = EventProbe.new

      actual = p.feed(input)
      report(input, input, actual)
      actual.should eq input
    end
  end

  describe "callback routing" do
    it "delivers keyboard events to on_key only" do
      inputs = ["\e[A", "\e[<0;10;20M"]
      p      = EventProbe.new
      inputs.each { |i| p.feed(i) }

      report(inputs, "keys: 1, mice: 1", "keys: #{p.keys.size}, mice: #{p.mice.size}")
      p.keys.size.should eq 1
      p.keys[0].should be_a Term::Input::Keyboard::KeyPress
      p.mice.size.should eq 1
      p.mice[0].should be_a Term::Input::Mouse::Press
    end

    it "delivers text and chord events to on_key" do
      inputs = ["\e[97;1:1;98u", "\e[97;1:3u"]
      p      = EventProbe.new
      inputs.each { |i| p.feed(i) }

      names = p.keys.map { |event| event.class.name.sub("Term::Input::Keyboard::", "") }
      report(inputs, ["KeyPress", "Text", "Chord", "KeyRelease"], names)
      names.should eq ["KeyPress", "Text", "Chord", "KeyRelease"]
    end

    it "delivers window events to on_window only" do
      input = "\e[I"
      p     = EventProbe.new
      p.feed(input)

      report(input, "keys: 0, mice: 0, windows: 1", "keys: #{p.keys.size}, mice: #{p.mice.size}, windows: #{p.windows.size}")
      p.keys.should be_empty
      p.mice.should be_empty
      p.windows.size.should eq 1
    end

    it "delivers unknown sequences to on_unknown" do
      input = "\e[1;2R"
      p     = EventProbe.new
      p.feed(input)

      report(input, "unknowns: 1", "unknowns: #{p.unknowns.size}")
      p.unknowns.size.should eq 1
      p.unknowns[0].should be_a Term::Input::Unknown::CSI
    end

    it "delivers to on_event and the filtered callback both" do
      input = "\e[<0;10;20M"
      p     = EventProbe.new
      p.feed(input)

      report(input, "events: 1, mice: 1", "events: #{p.events.size}, mice: #{p.mice.size}")
      p.events.size.should eq 1
      p.mice.size.should eq 1
    end

    it "supports multiple handlers" do
      first  = [] of Term::Input::Event
      second = [] of Term::Input::Event

      filter = Term::Seq::InputFilter.new
      events = Term::Input::Events.new(filter)
      events.on_event { |e| first << e }
      events.on_event { |e| second << e }
      filter.feed("\e[A".to_slice)

      report("\\e[A", "first: 1, second: 1", "first: #{first.size}, second: #{second.size}")
      first.size.should eq 1
      second.size.should eq 1
    end
  end

  describe "chunk boundaries" do
    it "waits for a split sequence to complete" do
      p = EventProbe.new

      p.feed("\e[")
      p.events.should be_empty
      p.feed("1;5")
      p.events.should be_empty
      p.feed("A")

      report(["\\e[", "1;5", "A"], "1 KeyPress(Up, Ctrl)", p.names)
      p.events.size.should eq 1
      key = p.events[0].as(Term::Input::Keyboard::KeyPress)
      key.key.should eq Term::Input::Keyboard::Functional::Up
      key.mods.ctrl?.should be_true
    end

    it "waits for a split SGR mouse sequence" do
      p = EventProbe.new

      p.feed("\e[<0;10;20")
      p.events.should be_empty
      p.feed("M")

      report(["\\e[<0;10;20", "M"], "1 Mouse::Press", p.names)
      p.events.size.should eq 1
      p.events[0].as(Term::Input::Mouse::Press).pos.xpx.should eq 10
    end

    it "emits several events from one chunk" do
      input = "\e[97u\e[98u\e[<0;1;1M"
      p     = EventProbe.new
      p.feed(input)

      report(input, ["Keyboard::KeyPress", "Keyboard::KeyPress", "Mouse::Press"], p.names)
      p.names.should eq ["Keyboard::KeyPress", "Keyboard::KeyPress", "Mouse::Press"]
    end
  end

  describe "lone escape" do
    it "releases an escape key press through the tick loop" do
      p = EventProbe.new(escape_ticks: 2)

      p.feed("\e")
      p.events.should be_empty
      p.tick
      p.events.should be_empty
      p.tick

      report("\\e then two ticks", "1 KeyPress(Escape)", p.names)
      p.events.size.should eq 1
      p.events[0].as(Term::Input::Keyboard::KeyPress).key.should eq Term::Input::Keyboard::Functional::Escape
    end

    it "does not fire when the escape starts a sequence" do
      p = EventProbe.new

      p.feed("\e")
      p.feed("[A")
      p.tick

      report(["\\e", "[A", "tick"], "1 KeyPress(Up)", p.names)
      p.events.size.should eq 1
      p.events[0].as(Term::Input::Keyboard::KeyPress).key.should eq Term::Input::Keyboard::Functional::Up
    end
  end

  describe "bracketed paste" do
    it "emits the pasted content" do
      input = "\e[200~hello\e[201~"
      p     = EventProbe.new
      p.feed(input)

      report(input, "pastes: [\"hello\"]", "pastes: #{p.pastes}")
      p.pastes.should eq ["hello"]
    end

    it "assembles a paste split across chunks" do
      p = EventProbe.new

      p.feed("\e[200~he")
      p.pastes.should be_empty
      p.feed("ll")
      p.pastes.should be_empty
      p.feed("o\e[201~")

      report(["\\e[200~he", "ll", "o\\e[201~"], ["hello"], p.pastes)
      p.pastes.should eq ["hello"]
    end

    it "keeps escape sequences inside the paste intact" do
      input = "\e[200~a\e[Ab\e[201~"
      p     = EventProbe.new
      p.feed(input)

      report(input, ["a\\e[Ab"], p.pastes)
      p.pastes.should eq ["a\e[Ab"]
      p.keys.should be_empty
    end

    it "emits events before and after a paste" do
      input = "\e[97u\e[200~y\e[201~\e[A"
      p     = EventProbe.new
      p.feed(input)

      report(input, ["Keyboard::KeyPress", "BracketedPaste", "Keyboard::KeyPress"], p.names)
      p.names.should eq ["Keyboard::KeyPress", "BracketedPaste", "Keyboard::KeyPress"]
      p.pastes.should eq ["y"]
    end

    it "handles an empty paste" do
      input = "\e[200~\e[201~"
      p     = EventProbe.new
      p.feed(input)

      report(input, [""], p.pastes)
      p.pastes.should eq [""]
    end

    it "forwards the paste bytes to the child unchanged" do
      input = "\e[200~hello\e[201~"
      p     = EventProbe.new

      actual = p.feed(input)
      report(input, input, actual)
      actual.should eq input
    end

    it "grows past the initial paste capacity" do
      payload = "z" * 5000
      p       = EventProbe.new

      p.feed("\e[200~")
      p.feed(payload)
      p.feed("\e[201~")

      report("5000 byte paste", "pastes: [5000 bytes]", "pastes size: #{p.pastes.size}, bytes: #{p.pastes[0].bytesize}")
      p.pastes.should eq [payload]
    end
  end

  describe "cell mapping" do
    it "maps mouse events once a resize report arrives" do
      inputs = ["\e[48;24;80;600;800t", "\e[<0;15;30M"]
      events = collect_events(inputs)

      pos = events[1].as(Term::Input::Mouse::Press).pos
      report(inputs, "col: 2, row: 2, x_off: 4, y_off: 4, px: 15, 30", pos)

      pos.col.should eq 2
      pos.row.should eq 2
      pos.x_off.should eq 4
      pos.y_off.should eq 4
      pos.xpx.should eq 15
      pos.ypx.should eq 30
    end

    it "leaves the derived fields unset while the cell size is unknown" do
      input  = "\e[<0;15;30M"
      events = collect_events([input])

      pos = events[0].as(Term::Input::Mouse::Press).pos
      report(input, "col: -1, row: -1, mapped: false", pos)

      pos.col.should eq -1
      pos.row.should eq -1
      pos.mapped?.should be_false
    end

    it "uses a cell pixel size report to track cell size" do
      inputs = ["\e[6;25;10t", "\e[<0;15;30M"]
      events = collect_events(inputs)

      pos = events[1].as(Term::Input::Mouse::Press).pos
      report(inputs, "col: 2, row: 2, x_off: 4, y_off: 4", pos)

      pos.col.should eq 2
      pos.row.should eq 2
      pos.x_off.should eq 4
      pos.y_off.should eq 4
    end

    it "keeps the cell size across a later mouse event" do
      inputs = ["\e[6;25;10t", "\e[<0;15;30M", "\e[<0;35;80M"]
      events = collect_events(inputs)

      pos = events[2].as(Term::Input::Mouse::Press).pos
      report(inputs, "col: 4, row: 4, x_off: 4, y_off: 4", pos)

      pos.col.should eq 4
      pos.row.should eq 4
      pos.x_off.should eq 4
      pos.y_off.should eq 4
    end

    it "exposes the tracked cell size" do
      p = EventProbe.new
      p.feed("\e[6;20;10t")

      report("\\e[6;20;10t", Term::Input::CellSize.new(w: 10, h: 20), p.cell)
      p.cell.should eq Term::Input::CellSize.new(w: 10, h: 20)
    end

    it "ignores a text area report for the cell size" do
      p = EventProbe.new
      p.feed("\e[8;24;80t")

      report("\\e[8;24;80t", nil, p.cell)
      p.cell.should be_nil
    end
  end

  describe "click synthesis" do
    it "emits a click after a press and release" do
      inputs = ["\e[<0;10;20M", "\e[<0;10;20m"]
      events = collect_events(inputs)

      report(inputs, ["Mouse::Press", "Mouse::Release", "Mouse::Click"], event_names(events))
      event_names(events).should eq ["Mouse::Press", "Mouse::Release", "Mouse::Click"]

      click = events[2].as(Term::Input::Mouse::Click)
      click.count.should eq 1
      click.button.should eq Term::Input::Mouse::Button::Left
      click.pos.xpx.should eq 10
    end

    it "counts a double and triple click" do
      inputs = ["\e[<0;10;20M", "\e[<0;10;20m"] * 3
      events = collect_events(inputs, click_interval: 5.seconds)

      counts = events.select(&.is_a?(Term::Input::Mouse::Click)).map(&.as(Term::Input::Mouse::Click).count)
      report(inputs, [1, 2, 3], counts)
      counts.should eq [1, 2, 3]
    end

    it "restarts the count for a different button" do
      inputs = ["\e[<0;10;20M", "\e[<0;10;20m", "\e[<2;10;20M", "\e[<2;10;20m"]
      events = collect_events(inputs, click_interval: 5.seconds)

      counts = events.select(&.is_a?(Term::Input::Mouse::Click)).map(&.as(Term::Input::Mouse::Click).count)
      report(inputs, [1, 1], counts)
      counts.should eq [1, 1]
    end

    it "restarts the count outside the slop radius" do
      inputs = ["\e[<0;10;20M", "\e[<0;10;20m", "\e[<0;40;20M", "\e[<0;40;20m"]
      events = collect_events(inputs, click_interval: 5.seconds)

      counts = events.select(&.is_a?(Term::Input::Mouse::Click)).map(&.as(Term::Input::Mouse::Click).count)
      report(inputs, [1, 1], counts)
      counts.should eq [1, 1]
    end

    it "keeps the count within the slop radius" do
      inputs = ["\e[<0;10;20M", "\e[<0;10;20m", "\e[<0;12;21M", "\e[<0;12;21m"]
      events = collect_events(inputs, click_interval: 5.seconds, drag_threshold: 100)

      counts = events.select(&.is_a?(Term::Input::Mouse::Click)).map(&.as(Term::Input::Mouse::Click).count)
      report(inputs, [1, 2], counts)
      counts.should eq [1, 2]
    end

    it "restarts the count after the interval expires" do
      inputs = ["\e[<0;10;20M", "\e[<0;10;20m"]
      p      = EventProbe.new(click_interval: 20.milliseconds)

      inputs.each { |i| p.feed(i) }
      sleep 60.milliseconds
      inputs.each { |i| p.feed(i) }

      counts = p.mice.select(&.is_a?(Term::Input::Mouse::Click)).map(&.as(Term::Input::Mouse::Click).count)
      report(inputs.to_s + " twice with a 60ms gap", [1, 1], counts)
      counts.should eq [1, 1]
    end

    it "emits no click for a release without a matching press" do
      input  = "\e[<0;10;20m"
      events = collect_events([input])

      report(input, ["Mouse::Release"], event_names(events))
      event_names(events).should eq ["Mouse::Release"]
    end
  end

  describe "drag synthesis" do
    it "passes motion below the threshold through untouched" do
      inputs = ["\e[<0;10;20M", "\e[<32;11;20M"]
      events = collect_events(inputs)

      report(inputs, ["Mouse::Press", "Mouse::Drag"], event_names(events))
      event_names(events).should eq ["Mouse::Press", "Mouse::Drag"]
    end

    it "emits a drag start once the threshold is crossed" do
      inputs = ["\e[<0;10;20M", "\e[<32;11;20M", "\e[<32;40;20M", "\e[<32;60;20M"]
      events = collect_events(inputs)

      expected = ["Mouse::Press", "Mouse::Drag", "Mouse::DragStart", "Mouse::Drag", "Mouse::Drag"]
      report(inputs, expected, event_names(events))
      event_names(events).should eq expected

      start = events[2].as(Term::Input::Mouse::DragStart)
      start.origin.xpx.should eq 10
      start.pos.xpx.should eq 40
      start.button.should eq Term::Input::Mouse::Button::Left
    end

    it "emits a drag end after the release" do
      inputs = ["\e[<0;10;20M", "\e[<32;40;20M", "\e[<0;40;20m"]
      events = collect_events(inputs)

      expected = ["Mouse::Press", "Mouse::DragStart", "Mouse::Drag", "Mouse::Release", "Mouse::DragEnd"]
      report(inputs, expected, event_names(events))
      event_names(events).should eq expected

      stop = events[4].as(Term::Input::Mouse::DragEnd)
      stop.origin.xpx.should eq 10
      stop.pos.xpx.should eq 40
    end

    it "emits no click when the press became a drag" do
      inputs = ["\e[<0;10;20M", "\e[<32;40;20M", "\e[<0;40;20m"]
      events = collect_events(inputs)

      clicks = events.select(&.is_a?(Term::Input::Mouse::Click))
      report(inputs, "0 clicks", "clicks: #{clicks.size}")
      clicks.should be_empty
    end

    it "restarts the click chain after a drag" do
      inputs = ["\e[<0;10;20M", "\e[<0;10;20m", "\e[<0;10;20M", "\e[<32;40;20M", "\e[<0;40;20m", "\e[<0;10;20M", "\e[<0;10;20m"]
      events = collect_events(inputs, click_interval: 5.seconds)

      counts = events.select(&.is_a?(Term::Input::Mouse::Click)).map(&.as(Term::Input::Mouse::Click).count)
      report(inputs, [1, 1], counts)
      counts.should eq [1, 1]
    end

    it "tracks buttons independently" do
      inputs = ["\e[<0;10;20M", "\e[<2;10;20M", "\e[<34;40;20M", "\e[<2;40;20m"]
      events = collect_events(inputs)

      expected = ["Mouse::Press", "Mouse::Press", "Mouse::DragStart", "Mouse::Drag", "Mouse::Release", "Mouse::DragEnd"]
      report(inputs, expected, event_names(events))
      event_names(events).should eq expected

      events[2].as(Term::Input::Mouse::DragStart).button.should eq Term::Input::Mouse::Button::Right
    end

    it "honours a custom threshold" do
      inputs = ["\e[<0;10;20M", "\e[<32;12;20M"]
      events = collect_events(inputs, drag_threshold: 1)

      expected = ["Mouse::Press", "Mouse::DragStart", "Mouse::Drag"]
      report(inputs, expected, event_names(events))
      event_names(events).should eq expected
    end

    it "keeps a drag alive across a leave" do
      inputs = ["\e[<0;10;20M", "\e[<32;40;20M", "\e[<256;0;0M", "\e[<0;60;20m"]
      events = collect_events(inputs)

      expected = ["Mouse::Press", "Mouse::DragStart", "Mouse::Drag", "Mouse::Leave", "Mouse::Enter", "Mouse::Release", "Mouse::DragEnd"]
      report(inputs, expected, event_names(events))
      event_names(events).should eq expected
    end
  end

  describe "enter synthesis" do
    it "emits no enter before the first mouse event" do
      input  = "\e[<0;10;20M"
      events = collect_events([input])

      report(input, ["Mouse::Press"], event_names(events))
      event_names(events).should eq ["Mouse::Press"]
    end

    it "emits an enter after a leave" do
      inputs = ["\e[<256;0;0M", "\e[<35;5;7M"]
      events = collect_events(inputs)

      report(inputs, ["Mouse::Leave", "Mouse::Enter", "Mouse::Hover"], event_names(events))
      event_names(events).should eq ["Mouse::Leave", "Mouse::Enter", "Mouse::Hover"]

      enter = events[1].as(Term::Input::Mouse::Enter)
      enter.pos.xpx.should eq 5
      enter.pos.ypx.should eq 7
    end

    it "emits one enter per leave" do
      inputs = ["\e[<256;0;0M", "\e[<35;5;7M", "\e[<35;6;7M"]
      events = collect_events(inputs)

      enters = events.select(&.is_a?(Term::Input::Mouse::Enter))
      report(inputs, "1 enter", "enters: #{enters.size}")
      enters.size.should eq 1
    end

    it "does not emit an enter for a repeated leave" do
      inputs = ["\e[<256;0;0M", "\e[<256;0;0M"]
      events = collect_events(inputs)

      report(inputs, ["Mouse::Leave", "Mouse::Leave"], event_names(events))
      event_names(events).should eq ["Mouse::Leave", "Mouse::Leave"]
    end
  end

  describe "chord tracking" do
    it "emits a chord on key release" do
      inputs = ["\e[97;1:1u", "\e[97;1:3u"]
      events = collect_events(inputs)

      report(inputs, ["Keyboard::KeyPress", "Keyboard::Chord", "Keyboard::KeyRelease"], event_names(events))

      events.size.should eq 3
      events[0].should be_a Term::Input::Keyboard::KeyPress
      events[1].should be_a Term::Input::Keyboard::Chord
      events[2].should be_a Term::Input::Keyboard::KeyRelease

      chord = events[1].as(Term::Input::Keyboard::Chord)
      chord.keys.should eq ['a'] of Term::Input::Keyboard::Key
    end

    it "tracks multiple concurrent keys" do
      inputs = ["\e[97;1:1u", "\e[98;1:1u", "\e[98;1:3u", "\e[97;1:3u"]
      events = collect_events(inputs)

      chords = events.select(&.is_a?(Term::Input::Keyboard::Chord)).map(&.as(Term::Input::Keyboard::Chord))
      report(inputs, "2 chords tracked", "chords: #{chords.map(&.keys)}")

      chords.size.should eq 2
      chords[0].keys.should eq ['a', 'b'] of Term::Input::Keyboard::Key
      chords[1].keys.should eq ['a'] of Term::Input::Keyboard::Key
    end

    it "ignores duplicate press events" do
      inputs = ["\e[97;1:1u", "\e[97;1:1u", "\e[97;1:3u"]
      events = collect_events(inputs)

      chords = events.select(&.is_a?(Term::Input::Keyboard::Chord)).map(&.as(Term::Input::Keyboard::Chord))
      report(inputs, "1 chord tracked", "chords size: #{chords.size}")

      chords.size.should eq 1
      chords[0].keys.should eq ['a'] of Term::Input::Keyboard::Key
    end
  end

  describe "state resets" do
    it "drops a pending press on reset" do
      p = EventProbe.new
      p.feed("\e[<0;10;20M")
      p.input.reset
      p.feed("\e[<0;10;20m")

      report(["press", "<reset>", "release"], ["Mouse::Press", "Mouse::Release"], p.names)
      p.names.should eq ["Mouse::Press", "Mouse::Release"]
    end

    it "drops an in flight drag on reset" do
      p = EventProbe.new
      p.feed("\e[<0;10;20M")
      p.feed("\e[<32;40;20M")
      p.input.reset
      p.feed("\e[<0;40;20m")

      expected = ["Mouse::Press", "Mouse::DragStart", "Mouse::Drag", "Mouse::Release"]
      report(["press", "drag", "<reset>", "release"], expected, p.names)
      p.names.should eq expected
    end

    it "resets the leave state" do
      p = EventProbe.new
      p.feed("\e[<256;0;0M")
      p.input.reset
      p.feed("\e[<35;5;7M")

      report(["leave", "<reset>", "hover"], ["Mouse::Leave", "Mouse::Hover"], p.names)
      p.names.should eq ["Mouse::Leave", "Mouse::Hover"]
    end

    it "resets the click chain" do
      p = EventProbe.new(click_interval: 5.seconds)
      p.feed("\e[<0;10;20M")
      p.feed("\e[<0;10;20m")
      p.input.reset
      p.feed("\e[<0;10;20M")
      p.feed("\e[<0;10;20m")

      counts = p.mice.select(&.is_a?(Term::Input::Mouse::Click)).map(&.as(Term::Input::Mouse::Click).count)
      report(["click", "<reset>", "click"], [1, 1], counts)
      counts.should eq [1, 1]
    end

    it "clears held keys" do
      p = EventProbe.new
      p.feed("\e[97;1:1u")
      p.input.reset
      p.feed("\e[97;1:3u")

      chords = p.keys.select(&.is_a?(Term::Input::Keyboard::Chord)).map(&.as(Term::Input::Keyboard::Chord))
      report(["press", "<reset>", "release"], "1 chord with empty keys", "chords: #{chords.map(&.keys)}")

      chords.size.should eq 1
      chords[0].keys.should be_empty
    end

    it "drops a partial paste" do
      p = EventProbe.new
      p.feed("\e[200~partial")
      p.input.reset
      p.feed("x\e[201~")

      report(["\\e[200~partial", "<reset>", "x\\e[201~"], ["x"], p.pastes)
      p.pastes.should eq ["x"]
    end
  end
end

describe "oversized numeric parameters" do
  it "does not crash on a huge kitty codepoint" do
    input = "\e[" + "9" * 40 + "u"
    p     = EventProbe.new
    p.feed(input)

    report(input[0, 12] + "...", "no crash", p.names)
    p.events.size.should be <= 1
  end

  it "does not crash on a huge modifier field" do
    input = "\e[97;" + "9" * 40 + "u"
    p     = EventProbe.new
    p.feed(input)

    report(input[0, 12] + "...", "no crash", p.names)
    p.events.size.should be <= 1
  end

  it "parses a modifier at the upper bound" do
    input  = "\e[97;256u"
    actual = parse_one(input)
    report(input, "KeyPress with all modifier bits", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq 'a'
    key.mods.value.should eq 255
  end

  it "rejects a modifier just past the upper bound" do
    input = "\e[97;257u"
    ok, events = parse_result(input)
    report(input, "ok: false, events: []", "ok: #{ok}, events: #{events}")

    ok.should be_false
    events.should be_empty
  end
end
