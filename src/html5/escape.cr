module HTML5
  extend self

  # These replacements permit compatibility with old numeric entities that
  # assumed Windows-1252 encoding.
  # https://html.spec.whatwg.org/multipage/syntax.html#consume-a-character-reference

  private REPLACEMENT_TABLE = {
    '\u20AC', # First entry is what 0x80 should be replaced with.
    '\u0081',
    '\u201A',
    '\u0192',
    '\u201E',
    '\u2026',
    '\u2020',
    '\u2021',
    '\u02C6',
    '\u2030',
    '\u0160',
    '\u2039',
    '\u0152',
    '\u008D',
    '\u017D',
    '\u008F',
    '\u0090',
    '\u2018',
    '\u2019',
    '\u201C',
    '\u201D',
    '\u2022',
    '\u2013',
    '\u2014',
    '\u02DC',
    '\u2122',
    '\u0161',
    '\u203A',
    '\u0153',
    '\u009D',
    '\u017E',
    '\u0178', # Last entry is 0x9F.
    # 0x00->'\uFFFD' is handled programmatically.
    # 0x0D->'\u000D' is a no-op.
  }

  private def encode_int(x)
    # Negative values are errorneous. Making it unsigned address the problem
    i = x.to_u32!
    case
    when i <= (1 << 7) - 1
      Bytes[x.to_u8!]
    when i <= (1 << 11) - 1
      res = Bytes.new(2)
      res[0] = (0b11000000 | (x >> 6).to_u8!).to_u8!
      res[1] = (0b10000000 | (x.to_u8! & 0b00111111)).to_u8!
      res
    when i > Char::MAX_CODEPOINT, i >= 0xD800 && i <= 0xDFFF
      '\uFFFD'.bytes
    when i <= (1 << 16) - 1
      res = Bytes.new(3)
      res[0] = (0b11100000 | (x >> 12).to_u8!).to_u8!
      res[1] = (0b10000000 | ((x >> 6).to_u8! & 0b00111111)).to_u8!
      res[2] = (0b10000000 | (x.to_u8! & 0b00111111)).to_u8!
      res
    else
      res = Bytes.new(4)
      res[0] = (0b11110000 | (x >> 18).to_u8!).to_u8!
      res[1] = (0b10000000 | ((x >> 12).to_u8! & 0b00111111)).to_u8!
      res[2] = (0b10000000 | ((x >> 6).to_u8! & 0b00111111)).to_u8!
      res[3] = (0b10000000 | (x.to_u8! & 0b00111111)).to_u8!
      res
    end
  end

  # unescape_entity reads an entity like "&lt;" from b[src:] and writes the
  # corresponding "<" to b[dst:], returning the incremented dst and src cursors.
  # Precondition: b[src] == '&' && dst <= src.
  # attribute should be true if parsing an attribute value.
  private def unescape_entity(b, dst, src, attribute)
    # https://html.spec.whatwg.org/multipage/syntax.html#consume-a-character-reference

    # i starts at 1 because we already know that s[0] == '&'.
    i, s = 1, b[src..]

    if s.size <= 1
      b[dst] = b[src]
      return {dst + 1, src + 1}
    end

    if s[i] == '#'.ord
      if s.size <= 3 # We need to have at least "&#."
        b[dst] = b[src]
        return {dst + 1, src + 1}
      end
      i += 1
      c = s[i].unsafe_chr
      hex = false
      if {'x', 'X'}.includes?(c)
        hex = true
        i += 1
      end

      x = 0
      while i < s.size
        c = s[i].unsafe_chr
        i += 1
        if hex && c.hex?
          x = 16 &* x &+ c.to_i(16)
          next
        elsif c.number?
          x = 10 &* x &+ c.to_i
          next
        end
        i -= 1 unless c == ';'
        break
      end
      if i <= 3 # No character matched.
        b[dst] = b[src]
        return {dst + 1, src + 1}
      end

      val = case x
            when 0x80..0x9F
              # Replace characters from Windows-1252 with UTF-8 equivalents.
              REPLACEMENT_TABLE[x - 0x80].bytes
            when 0,
                 .>(Char::MAX_CODEPOINT),
                 0xD800..0xDFFF # unicode surrogate characters
              # Replace invalid characters with replacement character.
              '\uFFFD'.bytes
            else
              # don't replace disallowed codepoints
              unless x == 0x007F ||
                     # unicode noncharacters
                     (0xFDD0..0xFDEF).includes?(x) ||
                     # last two of each plane (nonchars) disallowed
                     x & 0xFFFF >= 0xFFFE ||
                     # unicode control characters expect space
                     (x < 0x0020 && !x.in?(0x0009, 0x000A, 0x000C))
                x.unsafe_chr.bytes
              end
            end

      val = val || encode_int(x)

      b[dst..].copy_from(val.to_unsafe, val.size)
      return {dst + val.size, src + i}
    end
    # Consume the maximum number of characters possible, with the
    # consumed characters matching one of the named references.
    while i < s.size
      c = s[i].unsafe_chr
      i += 1
      # Lower-cased characters are more common in entities, so we check them for first
      next if ('a'..'z').includes?(c) || ('A'..'Z').includes?(c) || ('0'..'9').includes?(c)
      i -= 1 unless c == ';'
      break
    end
    name = String.new(s[1...i])
    if name.empty?
      # No-op
    elsif attribute && name[name.bytesize - 1] != ';' && s.size > i && s[i] == '='.ord
      # No-op
    elsif (x = ENTITY[name]?) && (x.ord != 0)
      x_b = x.bytes
      b[dst..].copy_from(x_b.to_unsafe, x_b.size)
      return {dst + x_b.size, src + i}
    elsif (x = ENTITY2[name]?) && (x[0].ord != 0)
      x_b = x[0].bytes
      b[dst..].copy_from(x_b.to_unsafe, x_b.size)
      dst1 = dst + x_b.size
      x_b = x[1].bytes
      b[dst1..].copy_from(x_b.to_unsafe, x_b.size)
      return {dst1 + x_b.size, src + i}
    elsif !attribute
      max_len = name.bytesize - 1
      max_len = LONGEST_ENTITY_WITHOUT_SEMICOLON if max_len > LONGEST_ENTITY_WITHOUT_SEMICOLON
      max_len.downto(2) do |j|
        if (x = ENTITY[name[...j]]?) && (x.ord != 0)
          x_b = x.bytes
          b[dst..].copy_from(x_b.to_unsafe, x_b.size)
          return {dst + x_b.size, src + j + 1}
        end
      end
    end

    dst1, src1 = dst + i, src + i
    b[dst...dst1].copy_from(b[src...src1].to_unsafe, dst1 - dst)
    {dst1, src1}
  end

  # unescape unescapes bytes's entities in-place, so that "a&lt;b" becomes "a<b".
  # attribute should be true if parsing an attribute value.
  protected def unescape(bytes, attribute)
    b = Bytes.new(bytes.size)
    b.copy_from(bytes.to_unsafe, b.size)
    b.each_with_index do |c, i|
      if c == '&'.ord
        dst, src = unescape_entity(b, i, i, attribute)
        while src < b.size
          c = b[src]
          if c == '&'.ord
            dst, src = unescape_entity(b, dst, src, attribute)
          else
            b[dst] = c
            dst, src = dst + 1, src + 1
          end
        end
        return b[0...dst]
      end
    end
    b
  end

  protected def lower(b)
    String.new(b).downcase.to_slice
  end

  private ESCAPED_CHARS = "&'<>\"\r"

  protected def escape(w, s)
    i = index_any(s, ESCAPED_CHARS)
    while i != -1
      w.write(s[...i].to_slice)
      esc = case s[i]
            when '&'
              "&amp;"
            when '\''
              #  "&#39;" is shorter than "&apos;" and apos was not in HTML until HTML5.
              "&#39;"
            when '<'
              "&lt;"
            when '>'
              "&gt;"
            when '"'
              # "&#34;" is shorter than "&quot;".
              "&#34;"
            when '\r'
              "&#13;"
            else
              raise HTMLException.new("unrecognized escape character")
            end

      s = s[i + 1..]
      w.write(esc.to_slice)
      i = index_any(s, ESCAPED_CHARS)
    end
    w.write(s.to_slice)
  end

  # escape_string escapes special characters like "<" to become "&lt;". It
  # escapes only five such characters: <, >, &, ' and ".
  # ```unescape_string(escape_string(s)) == s``` always holds, but the converse isn't
  # always true.
  def escape_string(s : String) : String
    return s if index_any(s, ESCAPED_CHARS) == -1
    String.build do |io|
      escape(io, s)
    end
  end

  # unescape_string unescapes entities like "&lt;" to become "<". It unescapes a
  # larger range of entities than escape_string escapes. For example, "&aacute;"
  # unescapes to "á", as does "&#225;" and "&xE1;".
  # unescape_string(escape_string(s)) == s always holds, but the converse isn't
  # always true.
  def unescape_string(s : String) : String
    s.each_char do |c|
      return String.new(unescape(s.to_slice, false)) if c == '&'
    end
    s
  end

  protected def index_any(str : String, chars : String | Char) : Int32
    return (str.index(chars) || -1) if chars.is_a?(Char)

    str.each_char_with_index do |c, i|
      return i if chars.index(c)
    end
    -1
  end
end
