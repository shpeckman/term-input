# src/input/events.cr
module Term::Input
  alias Event = Keyboard::Event | Mouse::Event | Window::Event | Unknown::Event | BracketedPaste
end

class Term::Input::Events
  DEFAULT_DRAG_THRESHOLD = 3
  DEFAULT_CLICK_INTERVAL = 400.milliseconds
  DEFAULT_CLICK_SLOP     = 4

  private ESC_BYTE      = 0x1B_u8
  private BUTTON_SLOTS  =       7
  private ORIGIN_UNSET  = Mouse::Pos.new(xpx: 0, ypx: 0)
  private PASTE_INITIAL = 4096

  private struct ButtonState
    getter origin    : Mouse::Pos
    getter? pressed  : Bool
    getter? dragging : Bool

    def initialize(@pressed : Bool = false, @dragging : Bool = false, @origin : Mouse::Pos = ORIGIN_UNSET)
    end
  end

  getter cell : CellSize? = nil

  @on_event   : Array(Event ->)           = [] of Event ->
  @on_key     : Array(Keyboard::Event ->) = [] of Keyboard::Event ->
  @on_mouse   : Array(Mouse::Event ->)    = [] of Mouse::Event ->
  @on_window  : Array(Window::Event ->)   = [] of Window::Event ->
  @on_unknown : Array(Unknown::Event ->)  = [] of Unknown::Event ->
  @on_paste   : Array(String ->)          = [] of String ->

  @held_keys : Array(Keyboard::Key) = [] of Keyboard::Key
  @paste = IO::Memory.new(PASTE_INITIAL)

  @buttons      = StaticArray(ButtonState, BUTTON_SLOTS).new(ButtonState.new)
  @mouse_inside = true

  @click_button : Mouse::Button? = nil
  @click_pos   = ORIGIN_UNSET
  @click_time  = Time.instant
  @click_count = 0

  def initialize(@filter         : Term::Mux::InputFilter,
                 @drag_threshold : Int32      = DEFAULT_DRAG_THRESHOLD,
                 @click_interval : Time::Span = DEFAULT_CLICK_INTERVAL,
                 @click_slop     : Int32      = DEFAULT_CLICK_SLOP)
    install
  end

  def on_event(&block : Event ->) : Nil
    @on_event << block
  end

  def on_key(&block : Keyboard::Event ->) : Nil
    @on_key << block
  end

  def on_mouse(&block : Mouse::Event ->) : Nil
    @on_mouse << block
  end

  def on_window(&block : Window::Event ->) : Nil
    @on_window << block
  end

  def on_unknown(&block : Unknown::Event ->) : Nil
    @on_unknown << block
  end

  def on_paste(&block : String ->) : Nil
    @on_paste << block
  end

  def reset : Nil
    @held_keys.clear
    @paste.clear
    @buttons      = StaticArray(ButtonState, BUTTON_SLOTS).new(ButtonState.new)
    @mouse_inside = true
    reset_clicks
  end

  private def install : Nil
    Keyboard::FINALS.each do |final|
      @filter.on_csi(final) { |token| key_rule(token) }
    end

    Mouse::FINALS.each do |final|
      @filter.on_csi(final, marker: '<') { |token| mouse_rule(token) }
    end

    @filter.on_csi(Window::FOCUS_GAINED) { emit(Window::FocusGained.new); Disposition.pass }
    @filter.on_csi(Window::FOCUS_LOST) { emit(Window::FocusLost.new); Disposition.pass }
    @filter.on_csi(Window::REPORT_FINAL) { |token| window_report_rule(token) }
    @filter.on_csi(Window::PRIVATE_FINAL, marker: '?') { |token| window_private_rule(token) }

    @filter.on_byte(ESC_BYTE) do
      dispatch_key(Keyboard::KeyPress.new(key: Keyboard::Functional::Escape, mods: Keyboard::Mods::None))
      Disposition.pass
    end

    @filter.on_paste { |token| paste_rule(token) }

    @filter.on_csi { |token| unknown_csi(token) }
    @filter.on_osc { |token| unknown_rule(token) { |t, cb| Unknown.osc(t) { |e| cb.call(e) } } }
    @filter.on_dcs { |token| unknown_rule(token) { |t, cb| Unknown.dcs(t) { |e| cb.call(e) } } }
    @filter.on_apc { |token| unknown_rule(token) { |t, cb| Unknown.apc(t) { |e| cb.call(e) } } }
  end

  private def key_rule(token : Token) : Disposition
    handled = Keyboard.parse(token) { |event| dispatch_key(event) }
    unknown_csi(token) unless handled
    Disposition.pass
  end

  private def mouse_rule(token : Token) : Disposition
    handled = Mouse.parse(token, @cell) { |event| dispatch_mouse(event) }
    unknown_csi(token) unless handled
    Disposition.pass
  end

  private def window_report_rule(token : Token) : Disposition
    handled = Window.parse_report(token) { |event| dispatch_window(event) }
    unknown_csi(token) unless handled
    Disposition.pass
  end

  private def window_private_rule(token : Token) : Disposition
    handled = Window.parse_private(token) { |event| dispatch_window(event) }
    unknown_csi(token) unless handled
    Disposition.pass
  end

  private def unknown_csi(token : Token) : Disposition
    Unknown.csi(token) { |event| emit(event) }
    Disposition.pass
  end

  private def unknown_rule(token : Token, & : Token, Proc(Unknown::Event, Nil) ->) : Disposition
    callback = ->(event : Unknown::Event) { emit(event) }
    yield token, callback
    Disposition.pass
  end

  private def paste_rule(token : Token) : Disposition
    case token.kind
    when .paste_start?
      @paste.clear
    when .paste_data?
      @paste.write(token.bytes)
    when .paste_end?
      emit(BracketedPaste.new(@paste.to_s))
      @paste.clear
    end
    Disposition.pass
  end

  private def dispatch_key(event : Keyboard::Event) : Nil
    case event
    when Keyboard::KeyPress
      @held_keys << event.key unless @held_keys.includes?(event.key)
      emit(event)
    when Keyboard::KeyRelease
      emit(Keyboard::Chord.new(keys: @held_keys.dup))
      @held_keys.delete(event.key)
      emit(event)
    else
      emit(event)
    end
  end

  private def dispatch_window(event : Window::Event) : Nil
    update_cell(event)
    emit(event)
  end

  private def update_cell(event : Window::Event) : Nil
    case event
    when Window::SizeReport
      if event.kind.cell_area_px? && event.w > 0 && event.h > 0
        @cell = CellSize.new(w: event.w, h: event.h)
      end
    when Window::Resize
      if event.w > 0 && event.h > 0
        cw    = event.w_px // event.w
        ch    = event.h_px // event.h
        @cell = CellSize.new(w: cw, h: ch) if cw > 0 && ch > 0
      end
    end
  end

  private def dispatch_mouse(event : Mouse::Event) : Nil
    case event
    when Mouse::Leave
      @mouse_inside = false
      emit(event)
    when Mouse::Press
      enter(event.mods, event.pos)
      @buttons[event.button.value.to_i] = ButtonState.new(pressed: true, origin: event.pos)
      emit(event)
    when Mouse::Drag
      enter(event.mods, event.pos)
      slot  = event.button.value.to_i
      state = @buttons[slot]
      if state.pressed? && !state.dragging? && dragged?(state.origin, event.pos)
        @buttons[slot] = ButtonState.new(pressed: true, dragging: true, origin: state.origin)
        emit(Mouse::DragStart.new(button: event.button, mods: event.mods, pos: event.pos, origin: state.origin))
      end
      emit(event)
    when Mouse::Release
      enter(event.mods, event.pos)
      slot  = event.button.value.to_i
      state = @buttons[slot]
      @buttons[slot] = ButtonState.new
      emit(event)

      if state.pressed?
        if state.dragging?
          reset_clicks
          emit(Mouse::DragEnd.new(button: event.button, mods: event.mods, pos: event.pos, origin: state.origin))
        else
          count = next_click_count(event.button, event.pos)
          emit(Mouse::Click.new(button: event.button, mods: event.mods, pos: event.pos, count: count))
        end
      end
    when Mouse::Hover
      enter(event.mods, event.pos)
      emit(event)
    when Mouse::Scroll
      enter(event.mods, event.pos)
      emit(event)
    else
      emit(event)
    end
  end

  private def enter(mods : Mouse::Mods, pos : Mouse::Pos) : Nil
    return if @mouse_inside
    @mouse_inside = true
    emit(Mouse::Enter.new(mods: mods, pos: pos))
  end

  private def dragged?(origin : Mouse::Pos, pos : Mouse::Pos) : Bool
    dx = pos.xpx - origin.xpx
    dy = pos.ypx - origin.ypx
    dx * dx + dy * dy >= @drag_threshold * @drag_threshold
  end

  private def next_click_count(button : Mouse::Button, pos : Mouse::Pos) : Int32
    now = Time.instant

    chained = @click_count > 0 &&
              @click_button == button &&
              now - @click_time <= @click_interval &&
              within_slop?(@click_pos, pos)

    @click_button = button
    @click_pos    = pos
    @click_time   = now
    @click_count  = chained ? @click_count + 1 : 1
    @click_count
  end

  private def within_slop?(a : Mouse::Pos, b : Mouse::Pos) : Bool
    dx = b.xpx - a.xpx
    dy = b.ypx - a.ypx
    dx * dx + dy * dy <= @click_slop * @click_slop
  end

  private def reset_clicks : Nil
    @click_button = nil
    @click_count  = 0
  end

  private def emit(event : Event) : Nil
    @on_event.each &.call(event)

    case event
    when Keyboard::Event
      @on_key.each &.call(event)
    when Mouse::Event
      @on_mouse.each &.call(event)
    when Window::Event
      @on_window.each &.call(event)
    when Unknown::Event
      @on_unknown.each &.call(event)
    when BracketedPaste
      @on_paste.each &.call(event.content)
    end
  end
end
