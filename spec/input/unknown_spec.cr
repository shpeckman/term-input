# spec/input/unknown_spec.cr
require "../spec_helper"

describe "unknown CSI sequences" do
  it "yields a raw CSI for an unrecognised final" do
    input  = "\e[1;2R"
    actual = parse_one(input)
    report(input, "Unknown::CSI(bytes: \\e[1;2R)", actual)

    actual.should be_a Term::Input::Unknown::CSI
    bytes_to_s(actual.as(Term::Input::Unknown::CSI).bytes).should eq "\e[1;2R"
  end

  it "keeps the private introducer in the raw body" do
    input  = "\e[?1000R"
    actual = parse_one(input)
    report(input, "Unknown::CSI(bytes: \\e[?1000R)", actual)

    actual.should be_a Term::Input::Unknown::CSI
    bytes_to_s(actual.as(Term::Input::Unknown::CSI).bytes).should eq "\e[?1000R"
  end

  it "keeps the DA2 introducer in the raw body" do
    input  = "\e[>1;2R"
    actual = parse_one(input)
    report(input, "Unknown::CSI(bytes: \\e[>1;2R)", actual)

    actual.should be_a Term::Input::Unknown::CSI
    bytes_to_s(actual.as(Term::Input::Unknown::CSI).bytes).should eq "\e[>1;2R"
  end

  it "yields nothing for an incomplete sequence" do
    events = parse_events("\e[1;2;3")
    report("\\e[1;2;3", "[] of Event", events)
    events.should be_empty
  end

  it "copies the bytes out of the filter buffer" do
    p     = EventProbe.new
    input = Bytes.new(6)
    "\e[1;2R".to_slice.copy_to(input)
    p.feed(input)

    csi = p.events[0].as(Term::Input::Unknown::CSI)
    input[2] = '9'.ord.to_u8

    report("mutating the source chunk after the event", "\\e[1;2R", bytes_to_s(csi.bytes))
    bytes_to_s(csi.bytes).should eq "\e[1;2R"
  end
end

describe "OSC parsing" do
  describe "terminators" do
    it "accepts ST" do
      input    = "\e]0;title\e\\"
      actual   = emitted?(input)
      expected = true
      report(input, expected, actual)
      actual.should be_true
    end

    it "accepts BEL" do
      input    = "\e]0;title\a"
      actual   = emitted?(input)
      expected = true
      report(input, expected, actual)
      actual.should be_true
    end

    it "yields nothing without a terminator" do
      events = parse_events("\e]0;title")
      report("\\e]0;title", "[] of Event", events)
      events.should be_empty
    end
  end

  describe "generic OSC" do
    it "yields the command and payload" do
      input  = "\e]0;my title\e\\"
      actual = parse_one(input)
      report(input, "OSC cmd: 0, bytes: 'my title'", actual)

      actual.should be_a Term::Input::Unknown::OSC
      osc = actual.as(Term::Input::Unknown::OSC)
      osc.cmd.should eq 0
      bytes_to_s(osc.bytes).should eq "my title"
    end

    it "yields an empty payload when there is no separator" do
      input  = "\e]7\e\\"
      actual = parse_one(input)
      report(input, "OSC cmd: 7, empty payload", actual)

      osc = actual.as(Term::Input::Unknown::OSC)
      osc.cmd.should eq 7
      osc.bytes.should be_empty
    end

    it "keeps inner separators in the payload" do
      input  = "\e]52;c;QQ==\a"
      actual = parse_one(input)
      report(input, "OSC cmd: 52, bytes: 'c;QQ=='", actual)

      osc = actual.as(Term::Input::Unknown::OSC)
      osc.cmd.should eq 52
      bytes_to_s(osc.bytes).should eq "c;QQ=="
    end

    it "rejects a non numeric command" do
      input    = "\e]abc;x\e\\"
      actual   = emitted?(input)
      expected = false
      report(input, expected, actual)
      actual.should be_false
    end

    it "rejects an empty command" do
      input    = "\e];payload\e\\"
      actual   = emitted?(input)
      expected = false
      report(input, expected, actual)
      actual.should be_false
    end

    it "yields an empty payload for a trailing separator" do
      input  = "\e]0;\e\\"
      actual = parse_one(input)
      report(input, "OSC cmd: 0, empty payload", actual)

      osc = actual.as(Term::Input::Unknown::OSC)
      osc.cmd.should eq 0
      osc.bytes.should be_empty
    end
  end
end

describe "DCS parsing" do
  it "yields a raw DCS" do
    input  = "\eP$r0m\e\\"
    actual = parse_one(input)
    report(input, "Unknown::DCS(bytes: $r0m)", actual)

    actual.should be_a Term::Input::Unknown::DCS
    bytes_to_s(actual.as(Term::Input::Unknown::DCS).bytes).should eq "$r0m"
  end

  it "yields nothing without a terminator" do
    events = parse_events("\eP1+r7878")
    report("\\eP1+r7878", "[] of Event", events)
    events.should be_empty
  end

  it "rejects an empty payload" do
    input    = "\eP\e\\"
    actual   = emitted?(input)
    expected = false
    report(input, expected, actual)
    actual.should be_false
  end
end

describe "APC parsing" do
  it "yields the payload" do
    input  = "\e_Gi=1,a=T;AAAA\e\\"
    actual = parse_one(input)
    report(input, "Unknown::APC(bytes: Gi=1,a=T;AAAA)", actual)

    actual.should be_a Term::Input::Unknown::APC
    bytes_to_s(actual.as(Term::Input::Unknown::APC).bytes).should eq "Gi=1,a=T;AAAA"
  end

  it "yields nothing without a terminator" do
    events = parse_events("\e_Gi=1;AAAA")
    report("\\e_Gi=1;AAAA", "[] of Event", events)
    events.should be_empty
  end

  it "rejects an empty payload" do
    input    = "\e_\e\\"
    actual   = emitted?(input)
    expected = false
    report(input, expected, actual)
    actual.should be_false
  end
end
