require "./atom"

module HTML5
  enum TokenType : UInt32
    # Error means that an error occurred during tokenization
    Error
    # Text means a text node
    Text
    # StartTag looks like <a>
    StartTag
    # EndTag looks like </a>
    EndTag
    # SelfClosing tag looks like <br/>
    SelfClosingTag
    # Comment looks like <!--x-->
    Comment
    # Doctype looks like <!DOCTYPE x>
    Doctype
  end

  # A Token consists of a TokenType and some data (tag name for start and end
  # tags, content for text, comments and doctypes). A tag Token may also contain
  # an array of Attributes. data is unescaped for all Tokens (it looks like "a<b"
  # rather than "a&lt;b"). For tag Tokens, data_atom is the atom for data, or
  # zero if data is not a known tag name.
  class Token
    property type : TokenType
    property data_atom : Atom::Atom
    property data : String
    property attr : Array(Attribute)

    def initialize(@type = TokenType::Error, @data_atom = Atom::Atom.zero, @data = "", @attr = Array(Attribute).new(0))
    end

    # returns a string representation of a tag Token's data and attr
    def tag_string
      return data if attr.size == 0
      buf = IO::Memory.new
      buf.write data.to_slice
      attr.each do |a|
        buf << " "
        buf << a.key
        buf << "=\""
        HTML5.escape(buf, a.val)
        buf << "\""
      end
      buf.to_s
    end

    def to_s
      case type
      when .error?
        ""
      when .text?
        HTML5.escape_string(data)
      when .start_tag?
        "<#{tag_string()}>"
      when .end_tag?
        "</#{tag_string()}>"
      when .self_closing_tag?
        "<#{tag_string()}/>"
      when .comment?
        "<!--#{data}-->"
      when .doctype?
        "<!DOCTYPE #{data}>"
      else
        raise HTMLException.new("Invalid Token")
      end
    end

    def to_s(io : IO) : Nil
      io << to_s
    end
  end

  # Span is a range of bytes in a Tokenizer's buffer. The start is inclusive,
  # the end is exclusive.
  # :nodoc:
  class Span
    property start : Int32
    property end : Int32

    def initialize(@start = 0, @end = 0)
    end

    def to_s(io : IO) : Nil
      io << "Span(start: #{start}, end: #{end})"
    end

    def clone
      Span.new(start, end)
    end
  end

  # Tokenizer returns a stream of HTML Tokens
  class Tokenizer
    # r is teh source of HTML of text
    @r : IO
    # tt is TokenType of the current token
    @tt : TokenType = TokenType::Error
    # read_err is the set when IO returned 0 byte.
    @read_err = false
    # eof is set to mark IO has been exhausted
    @eof = false
    @exception : Exception? = nil
    # buf[raw.start...raw.end] holds the raw bytes of the current token.
    # buf[raw.end:] is buffered input that will yield future tokens.
    @raw : Span = Span.new
    @buf : Bytes = Bytes.empty
    # max_buf limits the data buffered in buf. A value of 0 means unlimited.
    @max_buf : Int32 = 0
    # buf[data.start...data.end] holds the raw bytes of the current token's data:
    # a text token's text, a tag token's tag name, etc.
    @data : Span = Span.new
    # pending_attr is the attribute key and value currently being tokenized.
    # When complete, pending_attr is pushed onto attr. n_attr_returned is
    # incremented on each call to TagAttr.
    @pending_attr : Array(Span) = Array(Span).new(2) { HTML5::Span.new }
    @attr : Array(Array(Span)) = Array(Array(Span)).new(0) { Array(HTML5::Span).new(2) }
    @n_attr_returned : Int32 = 0
    # raw_tag is the "script" in "</script>" that closes the next token. If
    # non-empty, the subsequent call to next will return a raw or RCDATA text
    # token: one that treats "<p>" as text instead of an element.
    # raw_tag's contents are HTML.lower-cased.
    @raw_tag : String = ""
    # text_is_raw is whether the current text token's data is not escaped.
    @text_is_raw = false
    # convert_nul is whether NUL bytes in the current token's data should
    # be converted into \ufffd replacement characters.
    @convert_nul = false
    # allow_cdata is whether CDATA sections are allowed in the current context.
    @allow_cdata = false

    # returns a new HTML5 Tokenizer for the given IO Reader.
    # The input is assumed to be UTF-8 encoded
    def initialize(@r)
    end

    # returns a new HTML5 Tokenizer for the given IO Reader, for
    # tokenizing an existing element's InnerHTML fragment. context_tag is that
    # element's tag, such as "div" or "iframe".
    #
    # For example, how the InnerHTML "a<b" is tokenized depends on whether it is
    # for a <p> or a <script> tag.
    #
    # The input is assumed to be UTF-8 encoded.
    def initialize(@r, context_tag : String)
      unless context_tag.empty?
        if ["iframe", "noembed", "noframes", "noscript", "plaintext", "script", "style", "title", "textarea", "xmp"].includes?(context_tag.downcase)
          @raw_tag = context_tag
        end
      end
    end

    # allow_cdata sets whether or not the tokenizer recognizes <![CDATA[foo]]> as
    # the text "foo". The default value is false, which means to recognize it as
    # a bogus comment "<!-- [CDATA[foo]] -->" instead.
    #
    # Strictly speaking, an HTML5 compliant tokenizer should allow CDATA if and
    # only if tokenizing foreign content, such as MathML and SVG. However,
    # tracking foreign-contentness is difficult to do purely in the tokenizer,
    # as opposed to the parser, due to HTML5 integration points: an <svg> element
    # can contain a <foreignObject> that is foreign-to-SVG but not foreign-to-
    # HTML5. For strict compliance with the HTML5 tokenization algorithm, it is the
    # responsibility of the user of a tokenizer to call allow_cdata as appropriate.
    # In practice, if using the tokenizer without caring whether MathML or SVG
    # CDATA is text or comments, such as tokenizing HTML5 to find all the anchor
    # text, it is acceptable to ignore this responsibility.
    def allow_cdata=(val)
      @allow_cdata = val
    end

    # next_is_not_raw_text instructs the tokenizer that the next token should not be
    # considered as 'raw text'. Some elements, such as script and title elements,
    # normally require the next token after the opening tag to be 'raw text' that
    # has no child elements. For example, tokenizing "<title>a<b>c</b>d</title>"
    # yields a start tag token for "<title>", a text token for "a<b>c</b>d", and
    # an end tag token for "</title>". There are no distinct start tag or end tag
    # tokens for the "<b>" and "</b>".
    #
    # This tokenizer implementation will generally look for raw text at the right
    # times. Strictly speaking, an HTML5 compliant tokenizer should not look for
    # raw text if in foreign content: <title> generally needs raw text, but a
    # <title> inside an <svg> does not. Another example is that a <textarea>
    # generally needs raw text, but a <textarea> is not allowed as an immediate
    # child of a <select>; in normal parsing, a <textarea> implies </select>, but
    # one cannot close the implicit element when parsing a <select>'s InnerHTML.
    # Similarly to allow_cdata, tracking the correct moment to override raw-text-
    # ness is difficult to do purely in the tokenizer, as opposed to the parser.
    # For strict compliance with the HTML5 tokenization algorithm, it is the
    # responsibility of the user of a tokenizer to call NextIsNotRawText as
    # appropriate. In practice, like allow_cdata, it is acceptable to ignore this
    # responsibility for basic usage.
    #
    # Note that this 'raw text' concept is different from the one offered by the
    # Tokenizer.raw method.
    def next_is_not_raw_text
      @raw_tag = ""
    end

    def eof?
      @eof
    end

    def exception?
      @exception
    end

    # read_byte returns the next byte from the input stream, doing a buffered read
    # from r into buf if necessary. buf[raw.start...raw.end] remains a contiguous byte
    # slice that holds all the bytes read so far for the current token.
    # It sets err if the underlying reader returns an error.
    private def read_byte
      if @raw.end >= @buf.size
        # Our buffer is exhausted and we have to read from IO. Check if the previous read
        # resulted in an error
        if @read_err
          @eof = true
          return 0_u8
        end

        # We copy buf[raw.start...raw.end] to the beginning of buf. If the size of
        # raw.end - raw.start is more than half the size of the buf, then we
        # allocate a new buffer before copy
        c = @buf.size
        c = 4096 if c == 0
        d = @raw.end - @raw.start
        if 2*d > c
          buf1 = Bytes.new(2*c)
        else
          buf1 = Bytes.new(c)
        end
        buf1.copy_from(@buf[@raw.start...@raw.end].to_unsafe, d) if @buf.size > 0
        if (x = @raw.start) && (x != 0)
          # Adjust the data/attr spans to refer to the same contents after copy.
          @data.start -= x
          @data.end -= x
          @pending_attr[0].start -= x
          @pending_attr[0].end -= x
          @pending_attr[1].start -= x
          @pending_attr[1].end -= x

          @attr.each do |a|
            a[0].start -= x
            a[0].end -= x
            a[1].start -= x
            a[1].end -= x
          end
        end
        @raw.start, @raw.end, @buf = 0, d, buf1[...d]
        # Now that we have copied the live bytes to the start of the buffer,
        # we read from IO r into the remainder.
        n = 0
        begin
          # n = @r.read(buf1[d...])
          n = read_at_least_one_byte(buf1[d...])
        rescue ex
          @exception = ex
        end

        if n == 0
          @read_err = true
          @eof = true
          return 0_u8
        end
        @buf = buf1[...d + n]
      end
      x = @buf[@raw.end]
      @raw.end += 1
      raise MaxBufferExceeded.new if @max_buf > 0 && @raw.end - @raw.start >= @max_buf
      x
    end

    # wraps an IO so taht reading cannot return (0, no IO::EOFError).
    # it returns NoProgress exception if the underlying IO::read returns (0, no IO::EOFError)
    # too many times in succession
    private def read_at_least_one_byte(b : Bytes) : Int32
      0.upto(99) do |_|
        n = @r.read(b)
        return n unless n < 0
      end
      raise NoProgressError.new
    end

    # buffered returns a slice containing data buffered but not yet tokenized
    def buffered
      @buf[@raw.end..]
    end

    # skips past any white space
    private def skip_white_space
      return if @eof
      loop do
        c = read_byte
        return if @eof
        case c.unsafe_chr
        when ' ', '\n', '\r', '\t', '\f'
          # No-op
        else
          @raw.end -= 1
          return
        end
      end
    end

    #  reads until the next "</foo>", where "foo" is z.rawTag and
    # is typically something like "script" or "textarea".
    private def read_raw_or_rcdata
      if @raw_tag == "script"
        read_script
        @text_is_raw = true
        @raw_tag = ""
        return
      end
      loop do
        c = read_byte
        break if @eof
        next unless c.unsafe_chr == '<'
        c = read_byte
        break if @eof
        if c.unsafe_chr != '/'
          @raw.end -= 1
          next
        end
        break if read_raw_end_tag || @eof
      end
      @data.end = @raw.end
      # A textarea's or title RCDATA can contain escaped entities
      @text_is_raw = !["textarea", "title"].includes?(@raw_tag)
      @raw_tag = ""
    end

    # read_raw_end_tag attempts to read a tag like "</foo>", where "foo" is raw_tag.
    # If it succeeds, it backs up the input position to reconsume the tag and returns true
    # otherwise returns false. The opening "</" has already been consumed.
    private def read_raw_end_tag
      0.upto(@raw_tag.size - 1) do |i|
        c = read_byte.unsafe_chr
        return false if @eof
        if c != @raw_tag[i] && c != @raw_tag[i] - ('a' - 'A')
          @raw.end -= 1
          return false
        end
      end
      c = read_byte.unsafe_chr
      return false if @eof
      if [' ', '\n', '\r', '\t', '\f', '/', '>'].includes?(c)
        # The 3 is 2 for leading "</" plus 1 for the trailing character c.
        @raw.end -= 3 + @raw_tag.size
        return true
      end
      @raw.end -= 1
      false
    end

    private def script_data
      loop do
        c = read_byte.unsafe_chr
        raise "" if @eof
        break script_data_less_than_sign if c == '<'
      end
    end

    private def script_data_less_than_sign
      c = read_byte.unsafe_chr
      raise "" if @eof
      script_data_end_tag_open if c == '/'
      script_data_escape_start if c == '!'
      @raw.end -= 1
      script_data
    end

    private def script_data_end_tag_open
      raise "" if read_raw_end_tag || @eof
      script_data
    end

    private def script_data_escape_start
      c = read_byte.unsafe_chr
      raise "" if @eof
      script_data_escape_start_dash if c == '-'
      @raw.end -= 1
      script_data
    end

    private def script_data_escape_start_dash
      c = read_byte.unsafe_chr
      raise "" if @eof
      script_data_escaped_dash_dash if c == '-'
      @raw.end -= 1
      script_data
    end

    private def script_data_escaped
      loop do
        c = read_byte.unsafe_chr
        raise "" if @eof
        break script_data_escaped_dash if c == '-'
        break script_data_escaped_less_than_sign if c == '<'
      end
    end

    private def script_data_escaped_dash
      c = read_byte.unsafe_chr
      raise "" if @eof
      return script_data_escaped_dash_dash if c == '-'
      return script_data_escaped_less_than_sign if c == '<'
      script_data_escaped
    end

    private def script_data_escaped_dash_dash
      loop do
        c = read_byte.unsafe_chr
        raise "" if @eof
        next if c == '-'
        break script_data_escaped_less_than_sign if c == '<'
        break script_data if c == '>'
        break script_data_escaped
      end
    end

    private def script_data_escaped_less_than_sign
      c = read_byte.unsafe_chr || raise ""
      raise "" if @eof
      script_data_escaped_end_tag_open if c == '/'
      script_data_double_escape_start if ('a'..'z').includes?(c) || ('A'..'Z').includes?(c)
      @raw.end -= 1
      script_data
    end

    private def script_data_escaped_end_tag_open
      raise "" if read_raw_end_tag || @eof
      script_data_escaped
    end

    private def script_data_double_escape_start
      @raw.end -= 1
      0.upto("script".size - 1) do |i|
        c = read_byte.unsafe_chr
        raise "" if @eof
        if c != "script"[i] && c != "SCRIPT"[i]
          @raw.end -= 1
          break script_data_escaped
        end
      end
      c = read_byte
      raise "" if @eof
      return script_data_double_escaped if [' ', '\n', '\r', '\t', '\f', '/', '>'].includes?(c.unsafe_chr)
      @raw.end -= 1
      script_data_escaped
    end

    private def script_data_double_escaped_dash_dash
      loop do
        c = read_byte.unsafe_chr
        return if @eof
        next if c == '-'
        break script_data_double_escaped_less_than_sign if c == '<'
        break script_data if c == '>'
        break script_data_double_escaped
      end
    end

    private def script_data_double_escaped_dash
      c = read_byte.unsafe_chr
      return if @eof
      return script_data_double_escaped_dash_dash if c == '-'
      return script_data_double_escaped_less_than_sign if c == '<'
      script_data_double_escaped
    end

    private def script_data_double_escaped_less_than_sign
      c = read_byte.unsafe_chr
      return if @eof
      script_data_double_escape_end if c == '/'
      @raw.end -= 1
      script_data_double_escaped
    end

    private def script_data_double_escaped
      loop do
        c = read_byte.unsafe_chr
        return if @eof
        break script_data_double_escaped_dash if c == '-'
        break script_data_double_escaped_less_than_sign if c == '<'
      end
    end

    private def script_data_double_escape_end
      if read_raw_end_tag
        @raw.end += "</script>".size
        script_data_escaped
      end
      raise "" if @eof
      script_data_double_escaped
    end

    # read_script reads until the next </script> tag, following the byzantine
    # rules for escaping/hiding the closing tag.
    private def read_script
      script_data
    rescue ex
      return
    ensure
      @data.end = @raw.end
    end

    # read_comment reads the next comment token starting with "<!--". The opening
    # "<!--" has already been consumed.
    private def read_comment
      @data.start = @raw.end
      begin
        dash_count = 2
        loop do
          c = read_byte
          if @eof
            # Ignore up to two dashes at EOF.
            dash_count = 2 if dash_count > 2
            @data.end = @raw.end - dash_count
            return
          end
          case c.unsafe_chr
          when '-'
            dash_count += 1
            next
          when '>'
            if dash_count >= 2
              @data.end = @raw.end - "-->".size
              return
            end
          when '!'
            if dash_count >= 2
              c = read_byte
              if @eof
                @data.end = @raw.end
                return
              end
              if c == '>'.ord
                @data.end = @raw.end - "--!>".size
                return
              end
            end
          else
            #
          end
          dash_count = 0
        end
      ensure
        if @data.end < @data.start
          # It's a comment with no data, like <!-->.
          @data.end = @data.start
        end
      end
    end

    # reads until the next ">"
    private def read_until_close_angle
      @data.start = @raw.end
      loop do
        c = read_byte
        if @eof
          @data.end = @raw.end
          return
        end
        if c == '>'.ord
          @data.end = @raw.end - ">".size
          return
        end
      end
    end

    # read_markup_declaration reads the next token starting with "<!". It might be
    # a "<!--comment-->", a "<!DOCTYPE foo>", a "<![CDATA[section]]>" or
    # <!a bogus comment". The opening "<!" has already been consumed.
    private def read_markup_declaration
      @data.start = @raw.end
      c = Bytes.new(2)
      0.upto(1) do |i|
        c[i] = read_byte
        if @eof
          @data.end = @raw.end
          return TokenType::Comment
        end
      end

      if c[0] == '-'.ord && c[1] == '-'.ord
        read_comment
        return TokenType::Comment
      end
      @raw.end -= 2
      return TokenType::Doctype if read_doctype
      if @allow_cdata && read_cdata
        @convert_nul = true
        return TokenType::Text
      end

      # It's a bogus comment
      read_until_close_angle
      TokenType::Comment
    end

    # read_doctype attempts to read a doctype declaration and returns true if
    # successful. The opening "<!" has already been consumed.
    private def read_doctype
      s = "DOCTYPE"
      0.upto(s.size - 1) do |i|
        c = read_byte
        if @eof
          @data.end = @raw.end
          return false
        end
        if c.unsafe_chr != s[i] && c.unsafe_chr != s[i] + ('a' - 'A')
          # Back up to read the fragment of "DOCTYPE" again.
          @raw.end = @data.start
          return false
        end
      end
      if skip_white_space && @eof
        @data.start = @raw.end
        @data.end = @raw.end
        return true
      end

      read_until_close_angle
      true
    end

    # read_cdata attempts to read a CDATA section and returns true if
    # successful. The opening "<!" has already been consumed.
    private def read_cdata
      s = "[CDATA["
      0.upto(s.size - 1) do |i|
        c = read_byte
        if @eof
          @data.end = @raw.end
          return false
        end
        if c.unsafe_chr != s[i]
          # Back up to read the fragment of "[CDATA[" again
          @raw.end = @data.start
          return false
        end
      end
      @data.start = @raw.end
      brackets = 0
      loop do
        c = read_byte
        if @eof
          @data.end = @raw.end
          return true
        end
        case c.unsafe_chr
        when ']'
          brackets += 1
        when '>'
          if brackets >= 2
            @data.end = @raw.end - "]]>".size
            return true
          end
          brackets = 0
        else
          brackets = 0
        end
      end
    end

    # start_tag_in returns whether the start tag in buf[z.data.start...z.data.end]
    # case-insensitively matches any element of ss.
    private def start_tag_in(*ss)
      ss.each do |s|
        next if @data.end - @data.start != s.size
        ret = 0.upto(s.size - 1) do |i|
          c = @buf[@data.start + i].unsafe_chr
          c = c.downcase if 'A' <= c && c <= 'Z'
          break true if c != s[i]
        end
        next if ret
        return true
      end
      false
    end

    # read_start_tag reads the next start tag token. The opening "<a" has already
    # been consumed, where 'a' means anything in [A-Za-z]
    private def read_start_tag
      read_tag(true)
      return TokenType::Error if @eof

      # Several tags flag the tokenizer's next token as raw
      c, raw = @buf[@data.start].unsafe_chr, false
      c += 'a' - 'A' if c.uppercase?
      case c
      when 'i'
        raw = start_tag_in("iframe")
      when 'n'
        raw = start_tag_in("noembed", "noframes", "noscript")
      when 'p'
        raw = start_tag_in("plaintext")
      when 's'
        raw = start_tag_in("script", "style")
      when 't'
        raw = start_tag_in("textarea", "title")
      when 'x'
        raw = start_tag_in("xmp")
      else
        #
      end
      @raw_tag = String.new(@buf[@data.start...@data.end]).downcase if raw

      # Look for a self-closing token like "<br/>".
      return TokenType::SelfClosingTag if !@eof && @buf[@raw.end - 2] == '/'.ord
      TokenType::StartTag
    end

    # read_tag reads the next tag token and its attributes. If saveAttr, those
    # attributes are saved in z.attr, otherwise z.attr is set to an empty slice.
    # The opening "<a" or "</a" has already been consumed, where 'a' means anything
    # in [A-Za-z].
    private def read_tag(save_attr)
      @attr.clear
      @n_attr_returned = 0
      # Read the tag name and attribute key/value pairs.
      read_tag_name
      return if skip_white_space && @eof

      loop do
        c = read_byte
        break if @eof || c == '>'.ord
        @raw.end -= 1
        read_tag_attr_key
        read_tag_attr_val

        # Save pending_attr if save_attr and that attribute has a non-empty key.
        if save_attr && @pending_attr[0].start != @pending_attr[0].end
          @attr << @pending_attr.clone
        end
        break if skip_white_space && @eof
      end
    end

    # read_tag_name sets z.data to the "div" in "<div k=v>". The reader (z.raw.end)
    # is positioned such that the first byte of the tag name (the "d" in "<div")
    # has already been consumed.
    private def read_tag_name
      @data.start = @raw.end - 1
      loop do
        c = read_byte
        if @eof
          @data.end = @raw.end
          return
        end

        if [' ', '\n', '\r', '\t', '\f'].includes?(c.unsafe_chr)
          @data.end = @raw.end - 1
          break
        elsif ['/', '>'].includes?(c.unsafe_chr)
          @raw.end -= 1
          @data.end = @raw.end
          break
        end
      end
    end

    # read_tag_attr_key sets pending_attr[0] to the "k" in "<div k=v>".
    private def read_tag_attr_key
      @pending_attr[0].start = @raw.end
      loop do
        c = read_byte
        if @eof
          @pending_attr[0].end = @raw.end
          break
        end
        if [' ', '\n', '\r', '\t', '\f', '/'].includes?(c.unsafe_chr)
          @pending_attr[0].end = @raw.end - 1
          break
        elsif ['=', '>'].includes?(c.unsafe_chr)
          @raw.end -= 1
          @pending_attr[0].end = @raw.end
          break
        end
      end
    end

    # read_tag_attr_val sets @pending_attr[1] to the "v" in "<div k=v>".
    private def read_tag_attr_val
      @pending_attr[1].start = @raw.end
      @pending_attr[1].end = @raw.end

      return if skip_white_space && @eof
      c = read_byte
      return if @eof
      unless c == '='.ord
        @raw.end -= 1
        return
      end

      return if skip_white_space && @eof
      quote = read_byte
      return if @eof
      case quote.unsafe_chr
      when '>'
        @raw.end -= 1
        return
      when '\'', '"'
        @pending_attr[1].start = @raw.end
        loop do
          c = read_byte
          if @eof
            @pending_attr[1].end = @raw.end
            return
          end
          if c == quote
            @pending_attr[1].end = @raw.end - 1
            return
          end
        end
      else
        @pending_attr[1].start = @raw.end - 1
        loop do
          c = read_byte
          if @eof
            @pending_attr[1].end = @raw.end
            return
          end
          if [' ', '\n', '\r', '\t', '\f'].includes?(c.unsafe_chr)
            @pending_attr[1].end = @raw.end - 1
            return
          elsif c == '>'.ord
            @raw.end -= 1
            @pending_attr[1].end = @raw.end
            return
          end
        end
      end
    end

    # scans the next token and returns its type.
    def next
      @raw.start = @raw.end
      @data.start = @raw.end
      @data.end = @raw.end

      if @eof
        @tt = TokenType::Error
        return @tt
      end

      unless @raw_tag.empty?
        if @raw_tag == "plaintext"
          # Read everything upto to EOF
          while !@eof
            read_byte
          end
          @data.end = @raw.end
          @text_is_raw = true
        else
          read_raw_or_rcdata
        end
        if @data.end > @data.start
          @tt = TokenType::Text
          @convert_nul = true
          return @tt
        end
      end

      @text_is_raw = false
      @convert_nul = false

      loop do
        c = read_byte
        break if @eof
        next unless c.unsafe_chr == '<'
        # Check if the '<' we have just read is part of a tag, comment
        # or doctype. If not, it's part of the accumulated text token.
        c = read_byte
        break if @eof
        c = c.unsafe_chr
        case
        when ('a'..'z').includes?(c) || ('A'..'Z').includes?(c)
          token_type = TokenType::StartTag
        when c == '/'
          token_type = TokenType::EndTag
        when ['!', '?'].includes?(c)
          # We use Comment TokenType to mean any of the "<!--actual comments-->",
          # "<!DOCTYPE declarations>" and "<?xml processing instructions?>"
          token_type = TokenType::Comment
        else
          # Reconsume the current character
          @raw.end -= 1
          next
        end

        # We have a non-text token, but we might have accumulated some text
        # before that. If so, we return the text first, and return the non-text
        # token on the subsequence call to next
        if (x = @raw.end - "<a".size) && (@raw.start < x)
          @raw.end = x
          @data.end = x
          @tt = TokenType::Text
          return @tt
        end
        case token_type
        when .start_tag?
          @tt = read_start_tag
          return @tt
        when .end_tag?
          c = read_byte
          break if @eof
          if c == '>'
            # "</>" does not generate a token at all. Generate an empty comment
            # to allow passthrough clients to pick up the data using Raw.
            # Reset the tokenizer state and start again.
            @tt = TokenType::Comment
            return @tt
          end
          if ('a'..'z').includes?(c.unsafe_chr) || ('A'..'Z').includes?(c.unsafe_chr)
            read_tag(false)

            @tt = @eof ? TokenType::Error : TokenType::EndTag
            return @tt
          end
          @raw.end -= 1
          read_until_close_angle
          @tt = TokenType::Comment
          return @tt
        when .comment?
          if c == '!'
            @tt = read_markup_declaration
            return @tt
          end
          @raw.end -= 1
          read_until_close_angle
          @tt = TokenType::Comment
          return @tt
        else
          #
        end
      end

      if @raw.start < @raw.end
        @data.end = @raw.end
        @tt = TokenType::Text
        return @tt
      end
      @tt = TokenType::Error
      @tt
    end

    # raw returns the unmodified text of the current token. Calling Next, Token,
    # Text, TagName or TagAttr may change the contents of the returned slice.
    #
    # The token stream's raw bytes partition the byte stream (up until an
    # ErrorToken). There are no overlaps or gaps between two consecutive token's
    # raw bytes. One implication is that the byte offset of the current token is
    # the sum of the lengths of all previous tokens' raw bytes.
    def raw : Bytes
      @buf[@raw.start...@raw.end]
    end

    private NUL         = '\u{0}'
    private REPLACEMENT = '\ufffd'

    # text returns the unescaped text of a text, comment or doctype token. The
    # contents of the returned slice may change on the next call to next.
    def text : Bytes?
      case @tt
      when .text?, .comment?, .doctype?
        s = @buf[@data.start...@data.end]
        @data.start = @raw.end
        @data.end = @raw.end
        s = HTML5.convert_new_lines(s)
        if (@convert_nul || @tt.comment?) && String.new(s).includes?(NUL)
          str = String.new(s)
          str = str.gsub(NUL, REPLACEMENT)
          s = str.to_slice
        end
        s = HTML5.unescape(s, false) unless @text_is_raw
        return s
      else
        nil
      end
      nil
    end

    # tag_name returns the HTML5.lower-cased name of a tag token (the "img" out of
    # <IMG SRC="foo">) and whether the tag has attributes.
    # The contents of the returned slice may change on the next call to next.
    def tag_name : {Bytes?, Bool}
      if @data.start < @data.end
        if @tt.start_tag? || @tt.end_tag? || @tt.self_closing_tag?
          s = @buf[@data.start...@data.end]
          @data.start = @raw.end
          @data.end = @raw.end
          return {HTML5.lower(s), @n_attr_returned < @attr.size}
        end
      end
      {nil, false}
    end

    # tag_attr returns the HTML5.lower-cased key and unescaped value of the next unparsed
    # attribute for the current tag token and whether there are more attributes.
    # The contents of the returned slices may change on the next call to next.
    def tag_attr : {Bytes?, Bytes?, Bool}
      if @n_attr_returned < @attr.size
        if @tt.start_tag? || @tt.self_closing_tag?
          x = @attr[@n_attr_returned]
          @n_attr_returned += 1
          key = @buf[x[0].start...x[0].end]
          val = @buf[x[1].start...x[1].end]
          return {HTML5.lower(key), HTML5.unescape(HTML5.convert_new_lines(val), true), @n_attr_returned < @attr.size}
        end
      end
      {nil, nil, false}
    end

    # token returns the current Token. The result's data and attr values remain
    # valid after subsequent next calls.
    def token : Token
      t = Token.new(type: @tt)
      case @tt
      when .text?, .comment?, .doctype?
        t.data = String.new(text() || Bytes.empty)
      when .start_tag?, .self_closing_tag?, .end_tag?
        name, more_attr = tag_name
        while more_attr
          key, val, more_attr = tag_attr
          if (k = key) && (v = val)
            t.attr << Attribute.new("", Atom.string(k), String.new(v))
          end
        end
        if (n = name) && (a = Atom.lookup(n)) && (a != Atom::Atom.zero)
          t.data_atom, t.data = a, a.string
        else
          t.data_atom, t.data = Atom::Atom.zero, String.new(name || Bytes.empty)
        end
      else
        #
      end
      t
    end

    # sets a limit on the amount of data buffered during tokenization.
    # A value of 0 means unlimited
    def max_buf=(n : Int32)
      @max_buf = n
    end
  end

  # converts "\r" and "\r\n" in s to "\n".
  # The conversion happens in place, but the resulting slice may be shorter
  protected def self.convert_new_lines(slice)
    s = slice.dup
    s.each_with_index do |c, i|
      next unless c == '\r'.ord

      src = i + 1
      if src >= s.size || s[src] != '\n'.ord
        s[i] = '\n'.ord.to_u8
        next
      end
      dst = i
      while src < s.size
        if s[src] == '\r'.ord
          src += 1 if src + 1 < s.size && s[src + 1] == '\n'.ord
          s[dst] = '\n'.ord.to_u8
        else
          s[dst] = s[src]
        end
        src += 1
        dst += 1
      end
      return s[...dst]
    end
    s
  end
end
