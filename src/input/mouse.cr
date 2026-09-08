# src/input/mouse.cr
module Term::Input::Mouse
  enum Button : UInt8
    Left
    Middle
    Right
    Aux8
    Aux9
    Aux10
    Aux11
  end

  @[Flags]
  enum Mods : UInt8
    Shift = 1
    Alt   = 2
    Ctrl  = 4

    def reserved? : Bool
      shift?
    end
  end

  record Pos,
    xpx   : Int32,
    ypx   : Int32,
    col   : Int32 = -1,
    row   : Int32 = -1,
    x_off : Int32 = -1,
    y_off : Int32 = -1 do
    def mapped? : Bool
      @col > 0 && @row > 0
    end
  end

  record Press,
    button : Button,
    mods   : Mods,
    pos    : Pos

  record Release,
    button : Button,
    mods   : Mods,
    pos    : Pos

  record Drag,
    button : Button,
    mods   : Mods,
    pos    : Pos

  record DragStart,
    button : Button,
    mods   : Mods,
    pos    : Pos,
    origin : Pos

  record DragEnd,
    button : Button,
    mods   : Mods,
    pos    : Pos,
    origin : Pos

  record Click,
    button : Button,
    mods   : Mods,
    pos    : Pos,
    count  : Int32

  record Hover,
    mods : Mods,
    pos  : Pos

  record Scroll,
    dir  : Dir,
    mods : Mods,
    pos  : Pos do
    enum Dir : UInt8
      Up
      Down
      Left
      Right
    end
  end

  record Enter,
    mods : Mods,
    pos  : Pos

  record Leave

  alias Event = Press | Release | Drag | DragStart | DragEnd | Click | Hover | Scroll | Enter | Leave

  MARKER = 0x3C_u8
  FINALS = StaticArray['M', 'm']

  private BIT_LEAVE  = 256
  private BIT_SCROLL =  64
  private BIT_MOTION =  32
  private BIT_AUX    = 128
  private BIT_SHIFT  =   4
  private BIT_ALT    =   8
  private BIT_CTRL   =  16
  private BIT_BUTTON =   3

  def self.mouse_pos(xpx : Int32, ypx : Int32, cell : CellSize?) : Pos
    return Pos.new(xpx: xpx, ypx: ypx) unless cell

    cw = cell.w
    ch = cell.h
    return Pos.new(xpx: xpx, ypx: ypx) unless cw > 0 && ch > 0

    x = xpx > 0 ? xpx - 1 : 0
    y = ypx > 0 ? ypx - 1 : 0

    Pos.new(xpx: xpx, ypx: ypx,
      col: x // cw + 1, row: y // ch + 1,
      x_off: x % cw, y_off: y % ch)
  end

  def self.parse(token : Term::Input::Token, cell : CellSize?, & : Event ->) : Bool
    return false unless token.marker == MARKER
    return false unless token.groups == 3
    return false unless Term::Input.plain_params?(token)

    b   = token.param?(0)
    xpx = token.param?(1)
    ypx = token.param?(2)
    return false unless b && xpx && ypx

    if (b & BIT_LEAVE) != 0
      yield Leave.new
      return true
    end

    mods = Mods::None
    mods |= Mods::Shift if (b & BIT_SHIFT) != 0
    mods |= Mods::Alt if (b & BIT_ALT) != 0
    mods |= Mods::Ctrl if (b & BIT_CTRL) != 0

    pos = mouse_pos(xpx, ypx, cell)

    if (b & BIT_SCROLL) != 0
      dir = case b & BIT_BUTTON
            when 0 then Scroll::Dir::Up
            when 1 then Scroll::Dir::Down
            when 2 then Scroll::Dir::Left
            else        Scroll::Dir::Right
            end
      yield Scroll.new(dir: dir, mods: mods, pos: pos)
    elsif (b & BIT_MOTION) != 0 && (b & BIT_BUTTON) == BIT_BUTTON
      yield Hover.new(mods: mods, pos: pos)
    else
      btn = if (b & BIT_AUX) != 0
              case b & BIT_BUTTON
              when 0 then Button::Aux8
              when 1 then Button::Aux9
              when 2 then Button::Aux10
              else        Button::Aux11
              end
            else
              case b & BIT_BUTTON
              when 1 then Button::Middle
              when 2 then Button::Right
              else        Button::Left
              end
            end

      if token.final == 'm'.ord.to_u8
        yield Release.new(button: btn, mods: mods, pos: pos)
      elsif (b & BIT_MOTION) != 0
        yield Drag.new(button: btn, mods: mods, pos: pos)
      else
        yield Press.new(button: btn, mods: mods, pos: pos)
      end
    end

    true
  end
end
