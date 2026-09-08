# src/input/unknown.cr
module Term::Input::Unknown
  record CSI,
    bytes : Bytes

  record OSC,
    cmd   : Int32,
    bytes : Bytes

  record DCS,
    bytes : Bytes

  record APC,
    bytes : Bytes

  alias Event = CSI | OSC | DCS | APC

  private FIELD_SEP = 0x3B_u8

  def self.csi(token : Term::Input::Token, & : Event ->) : Bool
    yield CSI.new(Term::Input.sealed(token.bytes))
    true
  end

  def self.osc(token : Term::Input::Token, & : Event ->) : Bool
    cmd = token.osc_code
    return false unless cmd

    content = token.content
    sep     = content.index(FIELD_SEP)
    data    = sep ? content[sep + 1, content.size - sep - 1] : Bytes.empty

    yield OSC.new(cmd, Term::Input.sealed(data))
    true
  end

  def self.dcs(token : Term::Input::Token, & : Event ->) : Bool
    body = Term::Input.string_body(token.bytes)
    return false if body.empty?

    yield DCS.new(Term::Input.sealed(body))
    true
  end

  def self.apc(token : Term::Input::Token, & : Event ->) : Bool
    body = token.content
    return false if body.empty?

    yield APC.new(Term::Input.sealed(body))
    true
  end
end
