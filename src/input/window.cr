# src/input/window.cr
module Term::Input::Window
  record FocusGained
  record FocusLost
  record Restored
  record Minimized

  record Resize,
    w    : Int32,
    h    : Int32,
    w_px : Int32,
    h_px : Int32

  record SizeReport,
    kind : Kind,
    w    : Int32,
    h    : Int32 do
    enum Kind : UInt8
      TextArea
      TextAreaPx
      CellAreaPx
    end
  end

  record ColorScheme,
    scheme : Scheme do
    enum Scheme : UInt8
      Dark  = 1
      Light = 2
    end
  end

  alias Event = FocusGained | FocusLost | Restored | Minimized | Resize | SizeReport | ColorScheme

  FOCUS_GAINED   = 'I'
  FOCUS_LOST     = 'O'
  REPORT_FINAL   = 't'
  PRIVATE_MARKER = 0x3F_u8
  PRIVATE_FINAL  = 'n'

  private SIZE_TEXT_AREA_PIXELS =  4
  private SIZE_CELL_PIXELS      =  6
  private SIZE_TEXT_AREA_CHARS  =  8
  private SIZE_RESIZE           = 48

  private MODE_VISIBILITY = 999
  private MODE_SCHEME     = 997

  def self.parse_private(token : Term::Input::Token, & : Event ->) : Bool
    return false unless token.marker == PRIVATE_MARKER
    return false unless token.groups == 2
    return false unless Term::Input.plain_params?(token)

    mode  = token.param?(0)
    state = token.param?(1)
    return false unless mode && state

    case {mode, state}
    when {MODE_VISIBILITY, 1}
      yield Restored.new
    when {MODE_VISIBILITY, 2}
      yield Minimized.new
    when {MODE_SCHEME, 1}
      yield ColorScheme.new(ColorScheme::Scheme::Dark)
    when {MODE_SCHEME, 2}
      yield ColorScheme.new(ColorScheme::Scheme::Light)
    else
      return false
    end

    true
  end

  def self.parse_report(token : Term::Input::Token, & : Event ->) : Bool
    return false unless token.marker == 0_u8
    return false unless Term::Input.plain_params?(token)

    code = token.param?(0)
    return false unless code

    case code
    when SIZE_RESIZE
      parse_resize(token) { |event| yield event }
    when SIZE_TEXT_AREA_PIXELS, SIZE_CELL_PIXELS, SIZE_TEXT_AREA_CHARS
      parse_size(code, token) { |event| yield event }
    else
      false
    end
  end

  private def self.parse_size(code : Int32, token : Term::Input::Token, & : Event ->) : Bool
    return false unless token.groups >= 3

    h = token.param?(1)
    w = token.param?(2)
    return false unless h && w

    kind = case code
           when SIZE_TEXT_AREA_PIXELS then SizeReport::Kind::TextAreaPx
           when SIZE_CELL_PIXELS      then SizeReport::Kind::CellAreaPx
           else                            SizeReport::Kind::TextArea
           end

    yield SizeReport.new(kind: kind, w: w, h: h)
    true
  end

  private def self.parse_resize(token : Term::Input::Token, & : Event ->) : Bool
    return false unless token.groups == 5

    h    = token.param?(1)
    w    = token.param?(2)
    h_px = token.param?(3)
    w_px = token.param?(4)
    return false unless h && w && h_px && w_px

    yield Resize.new(w: w, h: h, w_px: w_px, h_px: h_px)
    true
  end
end
