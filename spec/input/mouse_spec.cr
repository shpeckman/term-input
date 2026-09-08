# spec/input/mouse_spec.cr
require "../spec_helper"

private CELL = Term::Input::CellSize.new(w: 10, h: 20)

describe Term::Input::Mouse::Mods do
  it "can check bitwise flag states" do
    input = "Shift | Ctrl"
    mods  = Term::Input::Mouse::Mods::Shift | Term::Input::Mouse::Mods::Ctrl

    expected = {shift: true, ctrl: true, alt: false}
    actual   = {shift: mods.shift?, ctrl: mods.ctrl?, alt: mods.alt?}
    report(input, expected, actual)

    mods.shift?.should be_true
    mods.ctrl?.should be_true
    mods.alt?.should be_false
  end

  it "reports shift as reserved by the terminal" do
    input = "None, Shift, Ctrl, Shift | Alt"

    expected = {none: false, shift: true, ctrl: false, shift_alt: true}
    actual = {
      none:      Term::Input::Mouse::Mods::None.reserved?,
      shift:     Term::Input::Mouse::Mods::Shift.reserved?,
      ctrl:      Term::Input::Mouse::Mods::Ctrl.reserved?,
      shift_alt: (Term::Input::Mouse::Mods::Shift | Term::Input::Mouse::Mods::Alt).reserved?,
    }
    report(input, expected, actual)

    Term::Input::Mouse::Mods::None.reserved?.should be_false
    Term::Input::Mouse::Mods::Shift.reserved?.should be_true
    Term::Input::Mouse::Mods::Ctrl.reserved?.should be_false
    (Term::Input::Mouse::Mods::Shift | Term::Input::Mouse::Mods::Alt).reserved?.should be_true
  end
end

describe Term::Input::Mouse::Pos do
  it "defaults the derived fields to the sentinel" do
    input = "Pos.new(xpx: 10, ypx: 20)"
    pos   = Term::Input::Mouse::Pos.new(xpx: 10, ypx: 20)

    expected = {col: -1, row: -1, x_off: -1, y_off: -1, mapped: false}
    actual   = {col: pos.col, row: pos.row, x_off: pos.x_off, y_off: pos.y_off, mapped: pos.mapped?}
    report(input, expected, actual)

    pos.col.should eq -1
    pos.row.should eq -1
    pos.x_off.should eq -1
    pos.y_off.should eq -1
    pos.mapped?.should be_false
  end

  it "is mapped once cell coordinates are present" do
    input = "Pos.new(xpx: 15, ypx: 30, col: 2, row: 2, x_off: 4, y_off: 9)"
    pos   = Term::Input::Mouse::Pos.new(xpx: 15, ypx: 30, col: 2, row: 2, x_off: 4, y_off: 9)

    report(input, true, pos.mapped?)
    pos.mapped?.should be_true
  end

  it "compares by value" do
    a = Term::Input::Mouse::Pos.new(xpx: 1, ypx: 2)
    b = Term::Input::Mouse::Pos.new(xpx: 1, ypx: 2)
    c = Term::Input::Mouse::Pos.new(xpx: 2, ypx: 1)

    report("Pos(1, 2) vs Pos(1, 2) vs Pos(2, 1)", "a == b, a != c", "a == b: #{a == b}, a == c: #{a == c}")
    a.should eq b
    a.should_not eq c
  end
end

describe "mouse gesture records" do
  it "carries an origin on drag records" do
    origin = Term::Input::Mouse::Pos.new(xpx: 10, ypx: 20)
    pos    = Term::Input::Mouse::Pos.new(xpx: 40, ypx: 20)

    start = Term::Input::Mouse::DragStart.new(button: Term::Input::Mouse::Button::Left, mods: Term::Input::Mouse::Mods::None, pos: pos, origin: origin)
    stop  = Term::Input::Mouse::DragEnd.new(button: Term::Input::Mouse::Button::Left, mods: Term::Input::Mouse::Mods::None, pos: pos, origin: origin)

    expected = {start_origin: origin, end_origin: origin}
    actual   = {start_origin: start.origin, end_origin: stop.origin}
    report("DragStart/DragEnd with origin (10, 20)", expected, actual)

    start.origin.should eq origin
    start.pos.should eq pos
    stop.origin.should eq origin
  end

  it "carries a click count" do
    click = Term::Input::Mouse::Click.new(button: Term::Input::Mouse::Button::Right, mods: Term::Input::Mouse::Mods::None, pos: Term::Input::Mouse::Pos.new(xpx: 1, ypx: 1), count: 2)

    report("Click.new(count: 2)", 2, click.count)
    click.count.should eq 2
    click.button.should eq Term::Input::Mouse::Button::Right
  end

  it "compares leave by value and carries nothing" do
    report("Leave.new", Term::Input::Mouse::Leave.new, Term::Input::Mouse::Leave.new)
    Term::Input::Mouse::Leave.new.should eq Term::Input::Mouse::Leave.new
  end
end

describe "mouse parsing" do
  it "parses a press" do
    input  = "\e[<0;10;20M"
    actual = parse_one(input)
    report(input, "Press at x:10, y:20, Left Button", actual)

    actual.should be_a Term::Input::Mouse::Press
    mouse = actual.as(Term::Input::Mouse::Press)
    mouse.pos.xpx.should eq 10
    mouse.pos.ypx.should eq 20
    mouse.button.should eq Term::Input::Mouse::Button::Left
    mouse.mods.none?.should be_true
  end

  it "parses a release" do
    input  = "\e[<0;10;20m"
    actual = parse_one(input)
    report(input, "Release with Left Button", actual)

    mouse = actual.as(Term::Input::Mouse::Release)
    mouse.button.should eq Term::Input::Mouse::Button::Left
  end

  it "parses a drag" do
    input  = "\e[<32;5;7M"
    actual = parse_one(input)
    report(input, "Drag with Left Button", actual)

    mouse = actual.as(Term::Input::Mouse::Drag)
    mouse.button.should eq Term::Input::Mouse::Button::Left
  end

  it "parses a hover" do
    input  = "\e[<35;5;7M"
    actual = parse_one(input)
    report(input, "Hover event", actual)
    actual.should be_a Term::Input::Mouse::Hover
  end

  it "parses wheel events" do
    dirs = {
      "\e[<64;1;1M" => Term::Input::Mouse::Scroll::Dir::Up,
      "\e[<65;1;1M" => Term::Input::Mouse::Scroll::Dir::Down,
      "\e[<66;1;1M" => Term::Input::Mouse::Scroll::Dir::Left,
      "\e[<67;1;1M" => Term::Input::Mouse::Scroll::Dir::Right,
    }

    dirs.each do |input, dir|
      actual = parse_one(input)
      report(input, "Scroll #{dir}", actual)
      actual.as(Term::Input::Mouse::Scroll).dir.should eq dir
    end
  end

  it "parses extended buttons" do
    input1  = "\e[<128;1;1M"
    actual1 = parse_one(input1)
    report(input1, "Press Aux8", actual1)
    actual1.as(Term::Input::Mouse::Press).button.should eq Term::Input::Mouse::Button::Aux8

    input2  = "\e[<131;1;1M"
    actual2 = parse_one(input2)
    report(input2, "Press Aux11", actual2)
    actual2.as(Term::Input::Mouse::Press).button.should eq Term::Input::Mouse::Button::Aux11
  end

  it "parses modifiers" do
    input  = "\e[<16;3;4M"
    actual = parse_one(input)
    report(input, "Press with Ctrl modifier", actual)

    mouse = actual.as(Term::Input::Mouse::Press)
    mouse.mods.ctrl?.should be_true
    mouse.mods.shift?.should be_false
    mouse.mods.alt?.should be_false
    mouse.button.should eq Term::Input::Mouse::Button::Left
  end

  it "parses combinations without disturbing the action or button" do
    input  = "\e[<28;1;1M"
    actual = parse_one(input)
    report(input, "Press with Shift, Alt, Ctrl modifiers", actual)

    mouse = actual.as(Term::Input::Mouse::Press)
    mouse.mods.shift?.should be_true
    mouse.mods.alt?.should be_true
    mouse.mods.ctrl?.should be_true
    mouse.mods.reserved?.should be_true
    mouse.button.should eq Term::Input::Mouse::Button::Left
  end

  it "parses large pixel coordinates" do
    input  = "\e[<0;1920;1080M"
    actual = parse_one(input)
    report(input, "Press at x:1920, y:1080", actual)

    mouse = actual.as(Term::Input::Mouse::Press)
    mouse.pos.xpx.should eq 1920
    mouse.pos.ypx.should eq 1080
  end

  it "rejects a missing coordinate" do
    input = "\e[<0;10M"
    ok, events = parse_result(input)
    report(input, "ok: false, events: []", "ok: #{ok}, events: #{events}")

    ok.should be_false
    events.should be_empty
  end

  it "rejects extra parameters" do
    input = "\e[<0;10;20;30M"
    ok, events = parse_result(input)
    report(input, "ok: false, events: []", "ok: #{ok}, events: #{events}")

    ok.should be_false
    events.should be_empty
  end

  it "rejects subparameters in a coordinate" do
    input = "\e[<0;10:1;20M"
    ok, events = parse_result(input)
    report(input, "ok: true with the subparameter ignored", "ok: #{ok}, events: #{events.size}")

    ok.should be_true
    events[0].as(Term::Input::Mouse::Press).pos.xpx.should eq 10
  end

  it "falls back to a raw CSI for an unknown final" do
    input  = "\e[<0;1;2X"
    actual = parse_one(input)
    report(input, "Unknown::CSI(bytes: \\e[<0;1;2X)", actual)

    actual.should be_a Term::Input::Unknown::CSI
    bytes_to_s(actual.as(Term::Input::Unknown::CSI).bytes).should eq "\e[<0;1;2X"
  end

  describe "leave" do
    it "parses a leave with no payload" do
      input    = "\e[<256;0;0M"
      actual   = parse_one(input)
      expected = Term::Input::Mouse::Leave.new
      report(input, expected, actual)
      actual.should eq expected
    end

    it "ignores every other bit when the leave bit is set" do
      input    = "\e[<292;800;600M"
      actual   = parse_one(input)
      expected = Term::Input::Mouse::Leave.new
      report(input, expected, actual)
      actual.should eq expected
    end

    it "ignores the cell size for a leave" do
      input    = "\e[<256;15;30M"
      actual   = parse_one(input, CELL)
      expected = Term::Input::Mouse::Leave.new
      report(input, expected, actual)
      actual.should eq expected
    end
  end

  describe "cell mapping" do
    it "leaves the derived fields unset without a cell size" do
      input  = "\e[<0;15;30M"
      actual = parse_one(input)
      report(input, "col: -1, row: -1, x_off: -1, y_off: -1", actual)

      pos = actual.as(Term::Input::Mouse::Press).pos
      pos.col.should eq -1
      pos.row.should eq -1
      pos.x_off.should eq -1
      pos.y_off.should eq -1
      pos.mapped?.should be_false
    end

    it "derives cell coordinates and sub cell offsets" do
      input  = "\e[<0;15;30M"
      actual = parse_one(input, CELL)
      report(input + " with cell 10x20", "col: 2, row: 2, x_off: 4, y_off: 9", actual)

      pos = actual.as(Term::Input::Mouse::Press).pos
      pos.xpx.should eq 15
      pos.ypx.should eq 30
      pos.col.should eq 2
      pos.row.should eq 2
      pos.x_off.should eq 4
      pos.y_off.should eq 9
      pos.mapped?.should be_true
    end

    it "maps the top left pixel to the first cell" do
      input  = "\e[<0;1;1M"
      actual = parse_one(input, CELL)
      report(input + " with cell 10x20", "col: 1, row: 1, x_off: 0, y_off: 0", actual)

      pos = actual.as(Term::Input::Mouse::Press).pos
      pos.col.should eq 1
      pos.row.should eq 1
      pos.x_off.should eq 0
      pos.y_off.should eq 0
    end

    it "maps the last pixel of a cell to that cell" do
      input  = "\e[<0;10;20M"
      actual = parse_one(input, CELL)
      report(input + " with cell 10x20", "col: 1, row: 1, x_off: 9, y_off: 19", actual)

      pos = actual.as(Term::Input::Mouse::Press).pos
      pos.col.should eq 1
      pos.row.should eq 1
      pos.x_off.should eq 9
      pos.y_off.should eq 19
    end

    it "clamps a zero coordinate to the first cell" do
      input  = "\e[<0;0;0M"
      actual = parse_one(input, CELL)
      report(input + " with cell 10x20", "col: 1, row: 1, x_off: 0, y_off: 0", actual)

      pos = actual.as(Term::Input::Mouse::Press).pos
      pos.col.should eq 1
      pos.row.should eq 1
      pos.x_off.should eq 0
      pos.y_off.should eq 0
    end

    it "ignores a degenerate cell size" do
      pos = Term::Input::Mouse.mouse_pos(15, 30, Term::Input::CellSize.new(w: 0, h: 20))
      report("mouse_pos(15, 30) with cell 0x20", "col: -1, row: -1", pos)

      pos.col.should eq -1
      pos.row.should eq -1
      pos.mapped?.should be_false
    end

    it "maps hover and scroll events too" do
      hover = parse_one("\e[<35;15;30M", CELL).as(Term::Input::Mouse::Hover)
      report("\e[<35;15;30M with cell 10x20", "col: 2, row: 2", hover)
      hover.pos.col.should eq 2
      hover.pos.row.should eq 2

      scroll = parse_one("\e[<64;15;30M", CELL).as(Term::Input::Mouse::Scroll)
      report("\e[<64;15;30M with cell 10x20", "col: 2, row: 2", scroll)
      scroll.pos.col.should eq 2
      scroll.pos.row.should eq 2
    end
  end
end
