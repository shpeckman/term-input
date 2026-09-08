# spec/input/keyboard_spec.cr
require "../spec_helper"

describe Term::Input::Keyboard::Mods do
  it "can check bitwise flag states" do
    input = "Shift | Ctrl | Meta | NumLock"
    mods  = Term::Input::Keyboard::Mods::Shift | Term::Input::Keyboard::Mods::Ctrl | Term::Input::Keyboard::Mods::Meta | Term::Input::Keyboard::Mods::NumLock

    expected = {shift: true, ctrl: true, meta: true, num_lock: true, alt: false, super: false, hyper: false, caps_lock: false}
    actual = {
      shift: mods.shift?, ctrl: mods.ctrl?, meta: mods.meta?, num_lock: mods.num_lock?,
      alt: mods.alt?, super: mods.super?, hyper: mods.hyper?, caps_lock: mods.caps_lock?,
    }

    report(input, expected, actual)

    mods.shift?.should be_true
    mods.ctrl?.should be_true
    mods.meta?.should be_true
    mods.num_lock?.should be_true
    mods.alt?.should be_false
    mods.super?.should be_false
    mods.hyper?.should be_false
    mods.caps_lock?.should be_false
  end
end

describe Term::Input::Keyboard::KeyPress do
  it "defaults the alternate key fields to nil" do
    input    = "KeyPress.new(key: 'a', mods: None)"
    actual   = Term::Input::Keyboard::KeyPress.new(key: 'a', mods: Term::Input::Keyboard::Mods::None)
    expected = {shifted: nil, base: nil}
    report(input, expected, {shifted: actual.shifted, base: actual.base})

    actual.shifted.should be_nil
    actual.base.should be_nil
  end

  it "carries alternate keys" do
    key = Term::Input::Keyboard::KeyPress.new(key: 'a', mods: Term::Input::Keyboard::Mods::Shift, shifted: 'A', base: 'a')
    report("KeyPress with shifted: 'A', base: 'a'", {shifted: 'A', base: 'a'}, {shifted: key.shifted, base: key.base})

    key.shifted.should eq 'A'
    key.base.should eq 'a'
  end
end

describe Term::Input::Keyboard::Text do
  it "carries a character" do
    input    = "Text.new('z')"
    actual   = Term::Input::Keyboard::Text.new('z').char
    expected = 'z'
    report(input, expected, actual)
    actual.should eq expected
  end
end

describe Term::Input::Keyboard::Chord do
  it "carries the keys" do
    input    = "Chord.new(['a'] of Term::Input::Keyboard::Key)"
    actual   = Term::Input::Keyboard::Chord.new(['a'] of Term::Input::Keyboard::Key).keys
    expected = ['a'] of Term::Input::Keyboard::Key
    report(input, expected, actual)
    actual.should eq expected
  end
end

describe "key parsing" do
  it "parses a bare kitty key" do
    input    = "\e[97u"
    expected = Term::Input::Keyboard::KeyPress.new(key: 'a', mods: Term::Input::Keyboard::Mods::None)
    actual   = parse_one(input)
    report(input, expected, actual)

    actual.should be_a Term::Input::Keyboard::KeyPress
    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq 'a'
    key.mods.should eq Term::Input::Keyboard::Mods::None
  end

  it "parses a key with modifiers" do
    input  = "\e[97;5u"
    actual = parse_one(input)
    report(input, "KeyPress with Ctrl modifier", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq 'a'
    key.mods.ctrl?.should be_true
  end

  it "parses a key with modifiers and an event type" do
    input  = "\e[97;2:3u"
    actual = parse_events(input)
    report(input, "2 events: Chord and KeyRelease with Shift modifier", actual)

    actual.size.should eq 2
    actual[0].should be_a Term::Input::Keyboard::Chord
    key = actual[1].as(Term::Input::Keyboard::KeyRelease)
    key.key.should eq 'a'
    key.mods.shift?.should be_true
  end

  it "clamps an out of range event type to press" do
    input  = "\e[97;2:9u"
    actual = parse_one(input)
    report(input, "KeyPress fallback for event type 9", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq 'a'
    key.mods.shift?.should be_true
  end

  it "yields a text event for an alternate codepoint" do
    input  = "\e[97;1;98u"
    actual = parse_events(input)
    report(input, "2 events: KeyPress('a') and Text('b')", actual)

    actual.size.should eq 2
    actual[0].as(Term::Input::Keyboard::KeyPress).key.should eq 'a'
    actual[1].should eq Term::Input::Keyboard::Text.new('b')
  end

  it "yields text alongside modifiers and an event type" do
    input  = "\e[97;2:2;65u"
    actual = parse_events(input)
    report(input, "2 events: KeyRepeat and Text('A')", actual)

    actual.size.should eq 2
    key = actual[0].as(Term::Input::Keyboard::KeyRepeat)
    key.mods.shift?.should be_true
    actual[1].should eq Term::Input::Keyboard::Text.new('A')
  end

  it "rejects a surrogate alternate codepoint after yielding the key" do
    input = "\e[97;1;55296u"
    ok, events = parse_result(input)
    report(input, "ok: false, events size: 1", "ok: #{ok}, events size: #{events.size}")

    ok.should be_false
    events.size.should eq 1
    events[0].should be_a Term::Input::Keyboard::KeyPress
  end

  it "rejects an out of range alternate codepoint after yielding the key" do
    input = "\e[97;1;1114112u"
    ok, events = parse_result(input)
    report(input, "ok: false, events size: 1", "ok: #{ok}, events size: #{events.size}")

    ok.should be_false
    events.size.should eq 1
  end

  it "parses legacy functional keys" do
    input  = "\e[3~"
    actual = parse_one(input)
    report(input, "KeyPress key: Delete", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq Term::Input::Keyboard::Functional::Delete
  end

  it "parses legacy functional keys with modifiers" do
    input  = "\e[3;5~"
    actual = parse_one(input)
    report(input, "KeyPress key: Delete, mods: Ctrl", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq Term::Input::Keyboard::Functional::Delete
    key.mods.ctrl?.should be_true
  end

  it "parses arrow keys" do
    { {'A', Term::Input::Keyboard::Functional::Up},
     {'B', Term::Input::Keyboard::Functional::Down},
     {'C', Term::Input::Keyboard::Functional::Right},
     {'D', Term::Input::Keyboard::Functional::Left} }.each do |final, expected_key|
      input  = "\e[#{final}"
      actual = parse_one(input)
      report(input, "KeyPress key: #{expected_key}", actual)

      key = actual.as(Term::Input::Keyboard::KeyPress)
      key.key.should eq expected_key
      key.mods.should eq Term::Input::Keyboard::Mods::None
    end
  end

  it "parses arrow keys with modifiers" do
    input  = "\e[1;3A"
    actual = parse_one(input)
    report(input, "KeyPress key: Up, mods: Alt", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq Term::Input::Keyboard::Functional::Up
    key.mods.alt?.should be_true
  end

  it "parses home and end" do
    input_home  = "\e[H"
    actual_home = parse_one(input_home)
    report(input_home, "KeyPress key: Home", actual_home)
    actual_home.as(Term::Input::Keyboard::KeyPress).key.should eq Term::Input::Keyboard::Functional::Home

    input_end  = "\e[F"
    actual_end = parse_one(input_end)
    report(input_end, "KeyPress key: End", actual_end)
    actual_end.as(Term::Input::Keyboard::KeyPress).key.should eq Term::Input::Keyboard::Functional::End
  end

  it "parses function key finals" do
    { {'P', Term::Input::Keyboard::Functional::F1},
     {'Q', Term::Input::Keyboard::Functional::F2},
     {'S', Term::Input::Keyboard::Functional::F4},
     {'E', Term::Input::Keyboard::Functional::KpBegin} }.each do |final, expected_key|
      input  = "\e[#{final}"
      actual = parse_one(input)
      report(input, "KeyPress key: #{expected_key}", actual)
      actual.as(Term::Input::Keyboard::KeyPress).key.should eq expected_key
    end
  end

  it "defaults the key to zero for kitty finals" do
    input_u  = "\e[u"
    actual_u = parse_one(input_u)
    report(input_u, "KeyPress key: Unknown", actual_u)
    actual_u.as(Term::Input::Keyboard::KeyPress).key.should eq Term::Input::Keyboard::Functional::Unknown

    input_tilde  = "\e[~"
    actual_tilde = parse_one(input_tilde)
    report(input_tilde, "KeyPress key: Unknown", actual_tilde)
    actual_tilde.as(Term::Input::Keyboard::KeyPress).key.should eq Term::Input::Keyboard::Functional::Unknown
  end

  it "defaults an empty modifier field to one" do
    input  = "\e[97;u"
    actual = parse_one(input)
    report(input, "KeyPress key: 'a', mods: None", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq 'a'
    key.mods.should eq Term::Input::Keyboard::Mods::None
    key.mods.shift?.should be_false
    key.mods.ctrl?.should be_false
  end

  it "defaults an empty modifier field on a legacy final" do
    input  = "\e[1;A"
    actual = parse_one(input)
    report(input, "KeyPress key: Up, mods: None", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq Term::Input::Keyboard::Functional::Up
    key.mods.should eq Term::Input::Keyboard::Mods::None
  end

  it "parses the escape key" do
    input  = "\e[27u"
    actual = parse_one(input)
    report(input, "KeyPress key: Escape", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq Term::Input::Keyboard::Functional::Escape
  end

  it "parses a high codepoint" do
    input  = "\e[233u"
    actual = parse_one(input)
    report(input, "KeyPress key: 'é' (233)", actual)

    key = actual.as(Term::Input::Keyboard::KeyPress)
    key.key.should eq 233.unsafe_chr
  end

  it "rejects a non numeric parameter" do
    input = "\e[9a7u"
    ok, events = parse_result(input)
    report(input, "ok: false, events: []", "ok: #{ok}, events: #{events}")

    ok.should be_false
    events.should be_empty
  end

  it "ignores a marked sequence with a key final" do
    input  = "\e[?31u"
    actual = parse_one(input)
    report(input, "Unknown::CSI(bytes: \\e[?31u)", actual)

    actual.should be_a Term::Input::Unknown::CSI
    bytes_to_s(actual.as(Term::Input::Unknown::CSI).bytes).should eq "\e[?31u"
  end

  describe "alternate keys" do
    it "parses a shifted alternate key" do
      input  = "\e[97:65;2u"
      actual = parse_one(input)
      report(input, "KeyPress key: 'a', shifted: 'A', mods: Shift", actual)

      key = actual.as(Term::Input::Keyboard::KeyPress)
      key.key.should eq 'a'
      key.shifted.should eq 'A'
      key.base.should be_nil
      key.mods.shift?.should be_true
    end

    it "parses shifted and base layout alternate keys" do
      input  = "\e[1089:1057:99;5u"
      actual = parse_one(input)
      report(input, "KeyPress key: 'с' (1089), shifted: 'С' (1057), base: 'c', mods: Ctrl", actual)

      key = actual.as(Term::Input::Keyboard::KeyPress)
      key.key.should eq 1089.unsafe_chr
      key.shifted.should eq 1057.unsafe_chr
      key.base.should eq 'c'
      key.mods.ctrl?.should be_true
    end

    it "parses a base layout key with an empty shifted field" do
      input  = "\e[97::99;5u"
      actual = parse_one(input)
      report(input, "KeyPress key: 'a', shifted: nil, base: 'c', mods: Ctrl", actual)

      key = actual.as(Term::Input::Keyboard::KeyPress)
      key.key.should eq 'a'
      key.shifted.should be_nil
      key.base.should eq 'c'
      key.mods.ctrl?.should be_true
    end

    it "parses alternate keys without modifiers" do
      input  = "\e[97:65u"
      actual = parse_one(input)
      report(input, "KeyPress key: 'a', shifted: 'A', mods: None", actual)

      key = actual.as(Term::Input::Keyboard::KeyPress)
      key.shifted.should eq 'A'
      key.mods.should eq Term::Input::Keyboard::Mods::None
    end

    it "carries alternate keys on repeats and releases" do
      input  = "\e[97:65;2:2u"
      actual = parse_one(input)
      report(input, "KeyRepeat shifted: 'A'", actual)

      repeat = actual.as(Term::Input::Keyboard::KeyRepeat)
      repeat.shifted.should eq 'A'

      input  = "\e[97:65;2:3u"
      actual = parse_events(input)
      report(input, "2 events: Chord and KeyRelease shifted: 'A'", actual)

      actual.size.should eq 2
      actual[0].should be_a Term::Input::Keyboard::Chord
      release = actual[1].as(Term::Input::Keyboard::KeyRelease)
      release.shifted.should eq 'A'
    end

    it "defaults alternate keys to nil when absent" do
      input  = "\e[97;5u"
      actual = parse_one(input)
      report(input, "KeyPress shifted: nil, base: nil", actual)

      key = actual.as(Term::Input::Keyboard::KeyPress)
      key.shifted.should be_nil
      key.base.should be_nil
    end

    it "parses alternate keys together with associated text" do
      input  = "\e[97:65;2;65u"
      actual = parse_events(input)
      report(input, "2 events: KeyPress(shifted: 'A') and Text('A')", actual)

      actual.size.should eq 2
      actual[0].as(Term::Input::Keyboard::KeyPress).shifted.should eq 'A'
      actual[1].should eq Term::Input::Keyboard::Text.new('A')
    end

    it "rejects a non numeric alternate key" do
      input = "\e[97:xu"
      ok, events = parse_result(input)
      report(input, "ok: false, events: []", "ok: #{ok}, events: #{events}")

      ok.should be_false
      events.should be_empty
    end
  end

  describe "multi codepoint text" do
    it "yields one text event per codepoint" do
      input  = "\e[97;1;104:105u"
      actual = parse_events(input)
      report(input, "3 events: KeyPress, Text('h'), Text('i')", actual)

      actual.size.should eq 3
      actual[0].should be_a Term::Input::Keyboard::KeyPress
      actual[1].should eq Term::Input::Keyboard::Text.new('h')
      actual[2].should eq Term::Input::Keyboard::Text.new('i')
    end

    it "yields multi codepoint text alongside alternate keys and an event type" do
      input  = "\e[97:65;2:2;104:105u"
      actual = parse_events(input)
      report(input, "3 events: KeyRepeat, Text('h'), Text('i')", actual)

      actual.size.should eq 3
      actual[0].should be_a Term::Input::Keyboard::KeyRepeat
      actual[1].should eq Term::Input::Keyboard::Text.new('h')
      actual[2].should eq Term::Input::Keyboard::Text.new('i')
    end

    it "yields text from several groups" do
      input  = "\e[97;1;104;105u"
      actual = parse_events(input)
      report(input, "3 events: KeyPress, Text('h'), Text('i')", actual)

      actual.size.should eq 3
      actual[1].should eq Term::Input::Keyboard::Text.new('h')
      actual[2].should eq Term::Input::Keyboard::Text.new('i')
    end

    it "rejects an out of range codepoint mid field after yielding prior events" do
      input = "\e[97;1;104:1114112u"
      ok, events = parse_result(input)
      report(input, "ok: false, events size: 2", "ok: #{ok}, events size: #{events.size}")

      ok.should be_false
      events.size.should eq 2
      events[0].should be_a Term::Input::Keyboard::KeyPress
      events[1].should eq Term::Input::Keyboard::Text.new('h')
    end

    it "rejects a surrogate codepoint mid field after yielding prior events" do
      input = "\e[97;1;104:55296u"
      ok, events = parse_result(input)
      report(input, "ok: false, events size: 2", "ok: #{ok}, events size: #{events.size}")

      ok.should be_false
      events.size.should eq 2
      events[1].should eq Term::Input::Keyboard::Text.new('h')
    end

    it "rejects a non numeric codepoint in the text field" do
      input = "\e[97;1;10a4u"
      ok, events = parse_result(input)
      report(input, "ok: false, events: []", "ok: #{ok}, events: #{events}")

      ok.should be_false
      events.should be_empty
    end
  end
end
