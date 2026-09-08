# examples/basic.cr
require "colorize"
require "../src/term-input"

module FullDemo
  TICK = 8.milliseconds

  @@logs    = [] of String
  @@mutex   = Mutex.new
  @@running = true

  def self.log(msg : String)
    @@mutex.synchronize do
      @@logs << msg
      @@logs.shift if @@logs.size > 15
    end
    render
  end

  def self.render
    @@mutex.synchronize do
      STDOUT.print "\e[H\e[2J"
      STDOUT.print "Terminal Input Event Viewer".colorize(:white).mode(:bold).to_s + "\r\n"
      STDOUT.print "Press " + "LeftCtrl+q".colorize(:yellow).to_s + " to quit, " + "LeftCtrl+c".colorize(:yellow).to_s + " to clear state.\r\n"
      STDOUT.print "═".colorize(:dark_gray).to_s * 60 + "\r\n\r\n"

      @@logs.each do |l|
        STDOUT.print l + "\r\n\r\n"
      end
      STDOUT.flush
    end
  end

  def self.format_pos(pos : Term::Input::Mouse::Pos) : String
    cell = if pos.mapped?
             "col: #{pos.col.to_s.colorize(:yellow)}, row: #{pos.row.to_s.colorize(:yellow)} | off: #{pos.x_off.to_s.colorize(:yellow)}, #{pos.y_off.to_s.colorize(:yellow)}"
           else
             "col: #{"?".colorize(:dark_gray)}, row: #{"?".colorize(:dark_gray)}"
           end

    "#{cell} | px: #{pos.xpx.to_s.colorize(:yellow)}, #{pos.ypx.to_s.colorize(:yellow)}"
  end

  def self.format_mods(mods : Term::Input::Mouse::Mods) : String
    base = mods.to_s.colorize(:green).to_s
    mods.reserved? ? base + " " + "(shift may be claimed for selection)".colorize(:dark_gray).to_s : base
  end

  def self.format_event(event : Term::Input::Event) : String
    name = event.class.name.sub("Term::Input::", "").colorize(:cyan).mode(:bold)

    details = case event
              when Term::Input::Keyboard::KeyPress, Term::Input::Keyboard::KeyRelease, Term::Input::Keyboard::KeyRepeat
                "key: #{event.key.inspect.colorize(:yellow)} | mods: #{event.mods.to_s.colorize(:green)} | shifted: #{event.shifted.inspect.colorize(:magenta)} | base: #{event.base.inspect.colorize(:magenta)}"
              when Term::Input::Keyboard::Chord
                keys_str = event.keys.map(&.inspect).join(", ").colorize(:yellow)
                "keys: [#{keys_str}]"
              when Term::Input::Keyboard::Text
                "char: #{event.char.inspect.colorize(:yellow)}"
              when Term::Input::Mouse::Press, Term::Input::Mouse::Release, Term::Input::Mouse::Drag
                "btn: #{event.button.to_s.colorize(:green)} | mods: #{format_mods(event.mods)} | #{format_pos(event.pos)}"
              when Term::Input::Mouse::DragStart, Term::Input::Mouse::DragEnd
                "btn: #{event.button.to_s.colorize(:green)} | mods: #{format_mods(event.mods)} | #{format_pos(event.pos)}\r\n   #{"From:".colorize(:dark_gray)} #{format_pos(event.origin)}"
              when Term::Input::Mouse::Click
                "btn: #{event.button.to_s.colorize(:green)} | count: #{event.count.to_s.colorize(:magenta).mode(:bold)} | mods: #{format_mods(event.mods)} | #{format_pos(event.pos)}"
              when Term::Input::Mouse::Scroll
                "dir: #{event.dir.to_s.colorize(:green)} | mods: #{format_mods(event.mods)} | #{format_pos(event.pos)}"
              when Term::Input::Mouse::Hover, Term::Input::Mouse::Enter
                "mods: #{format_mods(event.mods)} | #{format_pos(event.pos)}"
              when Term::Input::Mouse::Leave
                "pointer left the window".colorize(:dark_gray).to_s
              when Term::Input::Window::Resize
                "cols: #{event.w.to_s.colorize(:yellow)}, rows: #{event.h.to_s.colorize(:yellow)} | px_w: #{event.w_px.to_s.colorize(:yellow)}, px_h: #{event.h_px.to_s.colorize(:yellow)}"
              when Term::Input::Window::SizeReport
                "kind: #{event.kind.to_s.colorize(:green)} | w: #{event.w.to_s.colorize(:yellow)}, h: #{event.h.to_s.colorize(:yellow)}"
              when Term::Input::Window::ColorScheme
                "scheme: #{event.scheme.to_s.colorize(:green)}"
              when Term::Input::BracketedPaste
                "content: #{event.content.inspect.colorize(:yellow)}"
              when Term::Input::Unknown::CSI, Term::Input::Unknown::DCS, Term::Input::Unknown::APC
                "bytes: #{String.new(event.bytes).inspect.colorize(:yellow)}"
              when Term::Input::Unknown::OSC
                "cmd: #{event.cmd.to_s.colorize(:green)} | bytes: #{String.new(event.bytes).inspect.colorize(:yellow)}"
              else
                event.inspect.sub(event.class.name, "").colorize(:dark_gray).to_s
              end

    "#{name} #{details}"
  end

  def self.run
    quit   = Channel(Nil).new
    mutex  = Mutex.new
    filter = Term::Mux::InputFilter.new
    input  = Term::Input::Events.new(filter)

    input.on_event do |event|
      log " #{format_event(event)}"
    end

    input.on_key do |event|
      if event.is_a?(Term::Input::Keyboard::Chord)
        target_quit  = [Term::Input::Keyboard::Functional::LeftControl, 'q']
        target_clear = [Term::Input::Keyboard::Functional::LeftControl, 'c']

        if event.keys.size == 2 && target_quit.all? { |k| event.keys.includes?(k) }
          quit.send(nil)
        elsif event.keys.size == 2 && target_clear.all? { |k| event.keys.includes?(k) }
          input.reset
          log " #{"State".colorize(:red).mode(:bold)} Cleared"
        end
      end
    end

    STDOUT.print "\e[?1049h"
    STDOUT.print "\e[?25l"
    STDOUT.print Term::Input::ENABLE_INPUT

    STDOUT.print "\e[>q"
    STDOUT.print "\e[?2004$p"
    STDOUT.print "\eP+q544e\e\\"
    STDOUT.print "\eP$qm\e\\"
    STDOUT.print "\e[?996n"
    STDOUT.print "\e[16t"

    STDOUT.flush

    render

    STDIN.raw do
      begin
        spawn do
          buf = Bytes.new(4096)
          while @@running
            n = STDIN.read(buf)
            break if n == 0
            mutex.synchronize { filter.feed(buf[0, n]) }
          end
        end

        spawn do
          while @@running
            sleep TICK
            mutex.synchronize { filter.tick }
          end
        end

        quit.receive
      ensure
        @@running = false
        STDOUT.print Term::Input::DISABLE_INPUT
        STDOUT.print "\e[?25h"
        STDOUT.print "\e[?1049l"
        STDOUT.flush
      end
    end
  end
end

FullDemo.run
