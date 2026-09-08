# src/input/keyboard.cr
module Term::Input::Keyboard
  @[Flags]
  enum Mods : UInt8
    Shift    =   1
    Alt      =   2
    Ctrl     =   4
    Super    =   8
    Hyper    =  16
    Meta     =  32
    CapsLock =  64
    NumLock  = 128
  end

  enum Functional
    Escape; Enter; Tab; Backspace; Insert; Delete
    Left; Right; Up; Down; PageUp; PageDown; Home; End
    CapsLock; ScrollLock; NumLock; PrintScreen; Pause; Menu
    F1; F2; F3; F4; F5; F6; F7; F8; F9; F10; F11; F12
    F13; F14; F15; F16; F17; F18; F19; F20; F21; F22; F23; F24
    F25; F26; F27; F28; F29; F30; F31; F32; F33; F34; F35
    Kp0; Kp1; Kp2; Kp3; Kp4; Kp5; Kp6; Kp7; Kp8; Kp9
    KpDecimal; KpDivide; KpMultiply; KpSubtract; KpAdd
    KpEnter; KpEqual; KpSeparator
    KpLeft; KpRight; KpUp; KpDown; KpPageUp; KpPageDown; KpHome; KpEnd
    KpInsert; KpDelete; KpBegin
    MediaPlay; MediaPause; MediaPlayPause; MediaReverse; MediaStop
    MediaFastForward; MediaRewind; MediaTrackNext; MediaTrackPrevious; MediaRecord
    LowerVolume; RaiseVolume; MuteVolume
    LeftShift; LeftControl; LeftAlt; LeftSuper; LeftHyper; LeftMeta
    RightShift; RightControl; RightAlt; RightSuper; RightHyper; RightMeta
    IsoLevel3Shift; IsoLevel5Shift
    Unknown
  end

  alias Key = Char | Functional

  record KeyPress,
    key     : Key,
    mods    : Mods,
    shifted : Key? = nil,
    base    : Key? = nil

  record KeyRepeat,
    key     : Key,
    mods    : Mods,
    shifted : Key? = nil,
    base    : Key? = nil

  record KeyRelease,
    key     : Key,
    mods    : Mods,
    shifted : Key? = nil,
    base    : Key? = nil

  record Text,
    char : Char

  record Chord,
    keys : Array(Key)

  alias Event = KeyPress | KeyRepeat | KeyRelease | Text | Chord

  FINALS = StaticArray['u', '~', 'A', 'B', 'C', 'D', 'E', 'F', 'H', 'P', 'Q', 'S']

  private TEXT_GROUP =        2
  private MAX_MODS   =      256
  private MAX_SCALAR = 0x10FFFF

  def self.parse(token : Term::Input::Token, & : Event ->) : Bool
    return false unless token.marker == 0_u8
    return false unless FINALS.includes?(token.final.unsafe_chr)
    return false unless Term::Input.plain_params?(token)

    final = token.final.unsafe_chr

    key     = token.param?(0)
    shifted = token.sub?(0, 1)
    base    = token.sub?(0, 2)
    mods    = token.param?(1)
    event   = token.sub?(1, 1)

    resolved_key  = key || (final == 'u' || final == '~' ? 0 : 1)
    resolved_mods = mods || 1
    resolved_evt  = event || 1
    resolved_evt  = 1 unless 1 <= resolved_evt <= 3

    return false unless 1 <= resolved_mods <= MAX_MODS

    parsed_mods = Mods.new((resolved_mods - 1).to_u8)
    parsed_key  = key_decode(resolved_key, final)
    shifted_key = shifted ? key_decode(shifted, final) : nil
    base_key    = base ? key_decode(base, final) : nil

    case resolved_evt
    when 2
      yield KeyRepeat.new(key: parsed_key, mods: parsed_mods, shifted: shifted_key, base: base_key)
    when 3
      yield KeyRelease.new(key: parsed_key, mods: parsed_mods, shifted: shifted_key, base: base_key)
    else
      yield KeyPress.new(key: parsed_key, mods: parsed_mods, shifted: shifted_key, base: base_key)
    end

    group = TEXT_GROUP
    while group < token.groups
      index = 0
      count = token.sub_count(group)
      while index < count
        codepoint = token.sub?(group, index)
        index += 1
        next unless codepoint
        return false if codepoint > MAX_SCALAR || 0xD800 <= codepoint <= 0xDFFF
        yield Text.new(codepoint.unsafe_chr)
      end
      group += 1
    end

    true
  end

  private def self.key_decode(codepoint : Int32, final : Char) : Key
    case final
    when 'u'
      key_decode_kitty(codepoint)
    when '~'
      key_decode_legacy_tilde(codepoint)
    else
      key_decode_legacy_alpha(final, codepoint)
    end
  end

  private def self.key_safe_char(codepoint : Int32) : Key
    if (0 <= codepoint <= 0xD7FF) || (0xE000 <= codepoint <= MAX_SCALAR)
      codepoint.unsafe_chr
    else
      Functional::Unknown
    end
  end

  private def self.key_decode_kitty(codepoint : Int32) : Key
    case codepoint
    when 27           then Functional::Escape
    when 13           then Functional::Enter
    when 9            then Functional::Tab
    when 127, 8       then Functional::Backspace
    when 57358        then Functional::CapsLock
    when 57359        then Functional::ScrollLock
    when 57360        then Functional::NumLock
    when 57361        then Functional::PrintScreen
    when 57362        then Functional::Pause
    when 57363        then Functional::Menu
    when 57376..57398 then Functional.new(Functional::F13.value + (codepoint - 57376))
    when 57399..57408 then Functional.new(Functional::Kp0.value + (codepoint - 57399))
    when 57409        then Functional::KpDecimal
    when 57410        then Functional::KpDivide
    when 57411        then Functional::KpMultiply
    when 57412        then Functional::KpSubtract
    when 57413        then Functional::KpAdd
    when 57414        then Functional::KpEnter
    when 57415        then Functional::KpEqual
    when 57416        then Functional::KpSeparator
    when 57417        then Functional::KpLeft
    when 57418        then Functional::KpRight
    when 57419        then Functional::KpUp
    when 57420        then Functional::KpDown
    when 57421        then Functional::KpPageUp
    when 57422        then Functional::KpPageDown
    when 57423        then Functional::KpHome
    when 57424        then Functional::KpEnd
    when 57425        then Functional::KpInsert
    when 57426        then Functional::KpDelete
    when 57427        then Functional::KpBegin
    when 57428..57437 then Functional.new(Functional::MediaPlay.value + (codepoint - 57428))
    when 57438        then Functional::LowerVolume
    when 57439        then Functional::RaiseVolume
    when 57440        then Functional::MuteVolume
    when 57441..57446 then Functional.new(Functional::LeftShift.value + (codepoint - 57441))
    when 57447..57452 then Functional.new(Functional::RightShift.value + (codepoint - 57447))
    when 57453        then Functional::IsoLevel3Shift
    when 57454        then Functional::IsoLevel5Shift
    when 0            then Functional::Unknown
    else                   key_safe_char(codepoint)
    end
  end

  private def self.key_decode_legacy_tilde(codepoint : Int32) : Key
    case codepoint
    when 2      then Functional::Insert
    when 3      then Functional::Delete
    when 5      then Functional::PageUp
    when 6      then Functional::PageDown
    when 7      then Functional::Home
    when 8      then Functional::End
    when 11..15 then Functional.new(Functional::F1.value + (codepoint - 11))
    when 17..21 then Functional.new(Functional::F6.value + (codepoint - 17))
    when 23, 24 then Functional.new(Functional::F11.value + (codepoint - 23))
    when 29     then Functional::Menu
    else             Functional::Unknown
    end
  end

  private def self.key_decode_legacy_alpha(final : Char, codepoint : Int32) : Key
    case final
    when 'A'           then Functional::Up
    when 'B'           then Functional::Down
    when 'C'           then Functional::Right
    when 'D'           then Functional::Left
    when 'H'           then Functional::Home
    when 'F'           then Functional::End
    when 'P', 'Q', 'S' then Functional.new(Functional::F1.value + (final.ord - 'P'.ord))
    when 'E'           then Functional::KpBegin
    else                    key_safe_char(codepoint)
    end
  end
end
