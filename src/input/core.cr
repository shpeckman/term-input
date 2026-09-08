# src/input/core.cr
module Term::Input
  alias Token = Term::Mux::Token
  alias Disposition = Term::Mux::Disposition

  record CellSize,
    w : Int32,
    h : Int32

  record BracketedPaste,
    content : String

  DIGIT_LOW  = 0x30_u8
  DELIM_HIGH = 0x3B_u8

  def self.plain_params?(token : Token) : Bool
    bytes = token.bytes
    stop  = bytes.size - 1
    i     = token.marker == 0_u8 ? 2 : 3
    while i < stop
      b = bytes.unsafe_fetch(i)
      return false if b < DIGIT_LOW || b > DELIM_HIGH
      i += 1
    end
    true
  end

  def self.sealed(bytes : Bytes) : Bytes
    copy = Bytes.new(bytes.size)
    bytes.copy_to(copy)
    Bytes.new(copy.to_unsafe, copy.size, read_only: true)
  end

  def self.string_body(bytes : Bytes) : Bytes
    stop = bytes.size
    if stop >= 1 && bytes[stop - 1] == 0x07_u8
      stop -= 1
    elsif stop >= 2 && bytes[stop - 2] == 0x1B_u8 && bytes[stop - 1] == 0x5C_u8
      stop -= 2
    end
    stop > 2 ? bytes[2, stop - 2] : Bytes.empty
  end
end
