# Module Atom provides integer codes (also known as atoms) for a fixed set of
# frequently occurring HTML5 strings: tag names and attribute keys such as "p"
# and "id".
#
# Sharing an atom's name between all elements with the same tag can result in
# fewer string allocations when tokenizing and parsing HTML5. Integer
# comparisons are also generally faster than string comparisons.
#
# The value of an atom's particular code is not guaranteed to stay the same
# between versions of this module. Neither is any ordering guaranteed:
# whether Atom::H1 < Atom::H2 may also change. The codes are not guaranteed to
# be dense. The only guarantees are that e.g. looking up "div" will yield
# Atom::Div, calling Atom::Div.to_s will return "div", and Atom::Div != 0.
module HTML5::Atom
  private HASH0        = 0x9acb0442_u32
  private MAX_ATOM_LEN =             25

  struct Atom
    protected getter val : UInt32

    def self.[](value : Int)
      new(value.to_u32)
    end

    def self.zero
      new(0_u32)
    end

    def to_s
      start = (@val >> 8).to_u32
      n = (@val & 0xff).to_u32
      return "" if start + n > ATOM_TEXT.size
      n = start &+ n

      ATOM_TEXT[start.to_i...n.to_i]
    end

    def to_s(io : IO) : Nil
      io << to_s
    end

    def string
      ATOM_TEXT[(@val >> 8)...(@val >> 8) &+ (@val & 0xff)]
    end

    def ==(o : Int)
      o.to_u32 == @val
    end

    def ==(o : Atom)
      @val == o.val
    end

    private def initialize(@val)
    end

    forward_missing_to @val
  end

  # returns the Atom whose name is s. It returns zero if there is no such Atom.
  # Lookup is case sensitive
  def self.lookup(s : Bytes) : Atom
    return Atom.zero if s.size == 0 || s.size > MAX_ATOM_LEN
    h = fnv(HASH0, s)
    a = TABLE[h & (TABLE.size - 1).to_u32]
    return a if (a & 0xff).to_i == s.size && match(a.string, s)
    a = TABLE[(h >> 16) & (TABLE.size - 1).to_u32]
    return a if (a & 0xff).to_i == s.size && match(a.string, s)
    Atom.zero
  end

  # returns a string whose contents are equal to s.
  def self.string(s : Bytes) : String
    a = lookup(s)
    return a.to_s unless a == 0
    String.new(s)
  end

  # computes the FNV hash with an arbitrary starting value h
  private def self.fnv(h : UInt32, s : Bytes) : UInt32
    s.each do |b|
      h ^= b.to_u32
      h &*= 16777619
    end
    h
  end

  private def self.match(s : String, t : Bytes)
    s.to_slice == t
  end
end

require "./*"
