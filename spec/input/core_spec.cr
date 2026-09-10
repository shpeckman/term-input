# spec/input/core_spec.cr
require "../spec_helper"

describe Term::Input::CellSize do
  it "carries the cell dimensions" do
    input = "CellSize.new(w: 10, h: 20)"
    cell  = Term::Input::CellSize.new(w: 10, h: 20)

    expected = {w: 10, h: 20}
    actual   = {w: cell.w, h: cell.h}
    report(input, expected, actual)

    cell.w.should eq 10
    cell.h.should eq 20
  end

  it "compares by value" do
    a = Term::Input::CellSize.new(w: 10, h: 20)
    b = Term::Input::CellSize.new(w: 10, h: 20)
    c = Term::Input::CellSize.new(w: 20, h: 10)

    report("CellSize(10, 20) vs CellSize(10, 20) vs CellSize(20, 10)", "a == b, a != c", "a == b: #{a == b}, a == c: #{a == c}")
    a.should eq b
    a.should_not eq c
  end
end

describe Term::Input::BracketedPaste do
  it "carries its content" do
    input    = %(BracketedPaste.new("hello"))
    actual   = Term::Input::BracketedPaste.new("hello").content
    expected = "hello"
    report(input, expected, actual)
    actual.should eq expected
  end
end

describe "Term::Input.plain_params?" do
  it "accepts digits and delimiters" do
    accepted = [] of Bool
    filter   = Term::Seq::InputFilter.new
    filter.on_csi('u') { |t| accepted << Term::Input.plain_params?(t); Term::Seq::Disposition.pass }
    filter.feed("\e[97:65;2:3u".to_slice)

    report("\\e[97:65;2:3u", [true], accepted)
    accepted.should eq [true]
  end

  it "rejects a private marker byte inside the parameters" do
    accepted = [] of Bool
    filter   = Term::Seq::InputFilter.new
    filter.on_csi('u') { |t| accepted << Term::Input.plain_params?(t); Term::Seq::Disposition.pass }
    filter.feed("\e[9<7u".to_slice)

    report("\\e[9<7u", [false], accepted)
    accepted.should eq [false]
  end

  it "skips the private marker" do
    accepted = [] of Bool
    filter   = Term::Seq::InputFilter.new
    filter.on_csi('n', marker: '?') { |t| accepted << Term::Input.plain_params?(t); Term::Seq::Disposition.pass }
    filter.feed("\e[?997;1n".to_slice)

    report("\\e[?997;1n", [true], accepted)
    accepted.should eq [true]
  end
end

describe "Term::Input.sealed" do
  it "copies the bytes and marks them read only" do
    source = Bytes.new(3)
    "abc".to_slice.copy_to(source)
    sealed = Term::Input.sealed(source)

    report("sealed(\"abc\")", "read_only copy", "#{String.new(sealed)}, read_only: #{sealed.read_only?}")
    String.new(sealed).should eq "abc"
    sealed.read_only?.should be_true

    source[0] = 'z'.ord.to_u8
    String.new(sealed).should eq "abc"
  end
end
