# spec/input/window_spec.cr
require "../spec_helper"

describe "window records" do
  it "stores resize dimensions" do
    input  = "Resize.new(80, 24, 800, 600)"
    resize = Term::Input::Window::Resize.new(w: 80, h: 24, w_px: 800, h_px: 600)

    expected = {w: 80, h: 24, w_px: 800, h_px: 600}
    actual   = {w: resize.w, h: resize.h, w_px: resize.w_px, h_px: resize.h_px}
    report(input, expected, actual)

    resize.w.should eq 80
    resize.h.should eq 24
    resize.w_px.should eq 800
    resize.h_px.should eq 600
  end

  it "compares by value" do
    report("FocusGained.new", Term::Input::Window::FocusGained.new, Term::Input::Window::FocusGained.new)
    Term::Input::Window::FocusGained.new.should eq Term::Input::Window::FocusGained.new

    report("SizeReport.new(TextArea, 80, 24)", Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::TextArea, w: 80, h: 24), Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::TextArea, w: 80, h: 24))
    Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::TextArea, w: 80, h: 24).should eq Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::TextArea, w: 80, h: 24)

    report("SizeReport.new(CellAreaPx, 10, 20) vs SizeReport.new(CellAreaPx, 20, 10)", "not equal", "checked by should_not")
    Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::CellAreaPx, w: 10, h: 20).should_not eq Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::CellAreaPx, w: 20, h: 10)
  end
end

describe Term::Input::Window::ColorScheme do
  it "carries the scheme" do
    input  = "ColorScheme.new(Dark)"
    actual = Term::Input::Window::ColorScheme.new(Term::Input::Window::ColorScheme::Scheme::Dark)

    report(input, Term::Input::Window::ColorScheme::Scheme::Dark, actual.scheme)
    actual.scheme.should eq Term::Input::Window::ColorScheme::Scheme::Dark
    actual.scheme.dark?.should be_true
    actual.scheme.light?.should be_false
  end

  it "uses the protocol numbers as enum values" do
    expected = {dark: 1, light: 2}
    actual = {
      dark:  Term::Input::Window::ColorScheme::Scheme::Dark.value,
      light: Term::Input::Window::ColorScheme::Scheme::Light.value,
    }
    report("Scheme::Dark.value, Scheme::Light.value", expected, actual)

    Term::Input::Window::ColorScheme::Scheme::Dark.value.should eq 1
    Term::Input::Window::ColorScheme::Scheme::Light.value.should eq 2
  end

  it "compares by value" do
    a = Term::Input::Window::ColorScheme.new(Term::Input::Window::ColorScheme::Scheme::Light)
    b = Term::Input::Window::ColorScheme.new(Term::Input::Window::ColorScheme::Scheme::Light)
    c = Term::Input::Window::ColorScheme.new(Term::Input::Window::ColorScheme::Scheme::Dark)

    report("ColorScheme(Light) vs ColorScheme(Light) vs ColorScheme(Dark)", "a == b, a != c", "a == b: #{a == b}, a == c: #{a == c}")
    a.should eq b
    a.should_not eq c
  end
end

describe "focus reports" do
  it "parses focus gained" do
    input    = "\e[I"
    expected = Term::Input::Window::FocusGained.new
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "parses focus lost" do
    input    = "\e[O"
    expected = Term::Input::Window::FocusLost.new
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end
end

describe "window report parsing" do
  it "parses a full resize report" do
    input    = "\e[48;24;80;600;800t"
    expected = Term::Input::Window::Resize.new(w: 80, h: 24, w_px: 800, h_px: 600)
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "parses text area pixel size" do
    input    = "\e[4;600;800t"
    expected = Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::TextAreaPx, w: 800, h: 600)
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "parses cell pixel size" do
    input    = "\e[6;20;10t"
    expected = Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::CellAreaPx, w: 10, h: 20)
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "parses text area character size" do
    input    = "\e[8;24;80t"
    expected = Term::Input::Window::SizeReport.new(kind: Term::Input::Window::SizeReport::Kind::TextArea, w: 80, h: 24)
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "rejects an unknown window code" do
    input = "\e[9;1;2t"
    ok, events = parse_result(input)
    report(input, "ok: false, events: []", "ok: #{ok}, events: #{events}")
    ok.should be_false
    events.should be_empty
  end

  it "rejects a truncated resize report" do
    input = "\e[48;24;80t"
    ok, events = parse_result(input)
    report(input, "ok: false, events: []", "ok: #{ok}, events: #{events}")
    ok.should be_false
    events.should be_empty
  end
end

describe "private report parsing" do
  it "parses restore" do
    input    = "\e[?999;1n"
    expected = Term::Input::Window::Restored.new
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "parses minimize" do
    input    = "\e[?999;2n"
    expected = Term::Input::Window::Minimized.new
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "parses a dark mode report" do
    input    = "\e[?997;1n"
    expected = Term::Input::Window::ColorScheme.new(Term::Input::Window::ColorScheme::Scheme::Dark)
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "parses a light mode report" do
    input    = "\e[?997;2n"
    expected = Term::Input::Window::ColorScheme.new(Term::Input::Window::ColorScheme::Scheme::Light)
    actual   = parse_one(input)
    report(input, expected, actual)
    actual.should eq expected
  end

  it "falls back to a raw CSI for an unknown scheme value" do
    input  = "\e[?997;3n"
    actual = parse_one(input)
    report(input, "Unknown::CSI(bytes: \\e[?997;3n)", actual)

    actual.should be_a Term::Input::Unknown::CSI
    bytes_to_s(actual.as(Term::Input::Unknown::CSI).bytes).should eq "\e[?997;3n"
  end

  it "delivers a colour scheme report through the event layer" do
    inputs = ["\e[?997;1n", "\e[?997;2n"]
    events = collect_events(inputs)

    schemes = events.map(&.as(Term::Input::Window::ColorScheme).scheme)
    report(inputs, [Term::Input::Window::ColorScheme::Scheme::Dark, Term::Input::Window::ColorScheme::Scheme::Light], schemes)

    events.size.should eq 2
    schemes[0].dark?.should be_true
    schemes[1].light?.should be_true
  end
end
