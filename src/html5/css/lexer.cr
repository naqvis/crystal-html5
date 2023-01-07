module CSS
  enum TokenType
    Astr          # *
    Bar           # |
    Colon         # :
    Comma         # ,
    Dimension     # 4n
    Dot           # .
    Function      # nth-child(
    Hash          # #foo
    Ident         # h2
    LeftBrace     # [
    Match         # =
    MatchDash     # |=
    MatchIncludes # ~=
    MatchPrefix   # ^=
    MatchSubStr   # *=
    MatchSuffix   # $=
    Not           # :not(
    Number        # 37
    Plus          # +
    RightBrace    # ]
    RightParen    # )
    Space         # \t \n\r\f
    String        # 'hello world'
    Sub           # -
    Greater       # >
    Tilde         # ~
    Comment       # /* comments */
    Error
    EOF

    def to_s
      case self
      when .astr?           then "*"
      when .bar?            then "|"
      when .colon?          then ":"
      when .comma?          then ","
      when .dot?            then "."
      when .hash?           then "#"
      when .left_brace?     then "["
      when .match?          then "="
      when .match_dash?     then "|="
      when .match_includes? then "~="
      when .match_prefix?   then "^="
      when .match_sub_str?  then "*="
      when .match_suffix?   then "$="
      when .not?            then ":not("
      when .plus?           then "+"
      when .right_brace?    then "]"
      when .right_paren?    then ")"
      when .sub?            then "-"
      when .greater?        then ">"
      when .tilde?          then "~"
      else
        super.upcase
      end
    end

    # not included
    # ':' may be ':not(', must check that first
    # '.' may be the beginning of a number
    def self.from(c : Char)
      case c
      when '*' then Astr
      when '|' then Bar
      when ',' then Comma
      when '[' then LeftBrace
      when '=' then Match
      when '+' then Plus
      when ']' then RightBrace
      when ')' then RightParen
      when '-' then Sub
      when '>' then Greater
      when '~' then Tilde
      else
        raise CSSException.new("invalid character '#{c}'")
      end
    end
  end

  private MatchChar = {'|' => TokenType::MatchDash,
                       '~' => TokenType::MatchIncludes,
                       '^' => TokenType::MatchPrefix,
                       '*' => TokenType::MatchSubStr,
                       '$' => TokenType::MatchSuffix} of Char => TokenType
  private CombinatorChar = {'+' => TokenType::Plus,
                            '>' => TokenType::Greater,
                            ',' => TokenType::Comma, # tilde ~ cannot be matched based on a single char due to '~='
  } of Char => TokenType

  private EOF = Char::ZERO

  private record Token, type : TokenType, val : String = "", start : Int32 = 0 do
    def to_s(io : IO) : Nil
      io << "type=#{type} val=#{val} start=#{start}"
    end
  end

  private alias State = Proc(Nil) | Nil

  private module TokenEmitter
    abstract def token : Token
  end

  class Lexer
    include TokenEmitter

    def initialize(@s : String, @last = 0, @pos = 0)
      @c = Channel(Token).new(2)
    end

    def token : Token
      @c.receive
    end

    def next
      return EOF if @pos >= @s.size
      r = @s.char_at(@pos)
      @pos += 1
      r
    end

    def peek
      return EOF if @pos >= @s.size
      @s.char_at(@pos)
    end

    def backup
      raise CSSException.new("backed up past last emitted token") if @pos < @last
      @pos -= 1
    end

    def emit(t : TokenType)
      raise CSSException.new("nothing to emit at pos #{@pos}") if @last == @pos
      val = @s[@last...@pos]
      val = "-1n" if t.dimension? && val == "-n"
      @c.send(Token.new(t, val, @last))
      @last = @pos
    end

    def errorf(err) : Nil
      @c.send(
        Token.new(TokenType::Error, err || "", @last)
      )
    end

    def eof : Nil
      raise CSSException.new("emitted eof without being at eof") unless @pos == @s.size
      raise CSSException.new("emitted eof with unevaluated tokens") unless @last == @pos

      @c.send(Token.new(TokenType::EOF, start: @last))
    end

    def parse_next
      loop do
        r = self.peek
        begin
          case r
          when EOF
            self.eof
            break
          when .ascii_number?, '.', '-' then parse_num_or_dot
          when .in_set?(" \t\r\n\f")    then parse_space
          when '\'', '"'                then parse_string
          when '#'                      then parse_hash
          when ':'                      then parse_colon
          when '/'                      then parse_comment
          else
            if MatchChar.has_key?(r)
              type = MatchChar[r]
              self.next
              if self.peek == '='
                self.next
                self.emit(type)
                next
              else
                self.backup
              end
            end
            type = TokenType.from(r) rescue nil
            if (typ = type)
              self.next
              self.emit(typ)
              next
            end
            parse_ident
          end
        rescue ex
          errorf(ex.message)
          return
        end
      end
    end

    def parse_space
      self.skip_space
      if self.peek == '~'
        self.next
        if self.peek == '='
          self.backup
          emit(TokenType::Space)
          self.next
          self.next
          emit(TokenType::MatchIncludes)
        else
          emit(TokenType::Tilde)
        end
        return
      end

      if type = CombinatorChar[self.peek]?
        self.next
        emit(type)
      else
        emit(TokenType::Space)
      end
    end

    def parse_colon
      raise CSSException.new("expected ':' before calling parse_colon") unless self.next == ':'

      chars = {"nN", "oO", "tT", "("}
      backup = 0
      chars.each do |c|
        unless c.includes?(self.peek)
          0.upto(backup - 1) do |_|
            self.backup
          end
          emit(TokenType::Colon)
          return
        end
        self.next
        backup += 1
      end
      emit(TokenType::Not)
    end

    def parse_num_or_dot
      r = self.next
      raise CSSException.new("expected '.','-' or 0-9 before calling parse_num_or_dot") unless r == '.' || r == '-' || r.ascii_number?

      seen_dot = r == '.'
      if seen_dot
        if !self.peek.ascii_number?
          emit(TokenType::Dot)
        end
        return
      end
      skip_nums
      if !seen_dot && self.peek == '.'
        self.next
        if !self.peek.ascii_number?
          self.backup
          emit(TokenType::Number)
          self.next
          emit(TokenType::Dot)
          return
        end
        skip_nums
      end

      ok = self.skip_ident
      ok ? emit(TokenType::Dimension) : emit(TokenType::Number)
    end

    def parse_string
      schar = self.next
      raise CSSException.new("expected ' or \" before calling parse_string") unless ['\'', '"'].includes?(schar)
      loop do
        case r = self.next
        when EOF              then raise("unmatched string quote")
        when '\n', '\r', '\f' then raise("invalid unescaped string character")
        when '\\'
          case self.peek
          when '\n', '\f' then self.next
          when '\r'
            self.next
            self.next if self.peek == '\n'
          else
            skip_escape
          end
        when schar
          emit(TokenType::String)
          return
        end
      end
    end

    def parse_ident
      ok = skip_ident
      if ok
        if self.peek == '('
          self.next
          emit(TokenType::Function)
        else
          emit(TokenType::Ident)
        end
        return
      else
        raise("unexpected char")
      end
    end

    def parse_hash
      raise CSSException.new("expected '#' before calling parse_hash") unless self.next == '#'

      first_char = true
      loop do
        case r = self.peek
        when '_', '-', .ascii_alphanumeric?, non_ascii(r) then self.next
        when '\\'
          self.next
          skip_escape
        else
          raise("expected identifier after '#'") if first_char
          emit(TokenType::Hash)
          return
        end
        first_char = false
      end
    end

    def parse_comment
      raise CSSException.new("expected '*' before calling parse_comment") unless self.next == '/' && self.peek == '*'

      while (c = self.next)
        break if c == '*' && self.peek == '/'
      end
      self.next
      emit(TokenType::Comment)
    end

    protected def non_ascii(c)
      c.ord > 0o177 && c != EOF
    end

    def skip_nums
      while (self.peek.number?)
        self.next
      end
    end

    def skip_space
      while (self.peek.in_set?(" \t\r\n\f"))
        self.next
      end
    end

    # skip_escape skips the characters following the escape character '\'.
    # it assumes that the lexer has already consumed this character.
    def skip_escape : Nil
      r = self.next
      if r.hex?
        # parse unicode
        0.upto(4) do |_|
          break unless self.peek.hex?
          self.next
        end
        case self.peek
        when ' ', '\t', '\n', '\f' then self.next
        when '\r'
          self.next
          self.next if self.peek == '\n'
        end
        return
      end
      case r
      when '\r', '\n', '\f' then raise("invalid character after escape")
      when EOF              then raise("invalid EOF after escape")
      end
      self.next
    end

    # skip_ident attempts to move the lexer to the end of the next identifier.
    # if return false, the lexer was not advanced.
    def skip_ident
      found = self.peek == '-'
      self.next if found
      case r = self.peek
      when '_', .ascii_letter?, non_ascii(r)
        found = true
        self.next
      when '\\'
        found = true
        self.next
        skip_escape
      else
        raise CSSException.new("expected identifier after '-'") if found
        return found
      end

      loop do
        case r = self.peek
        when '_', '-', .ascii_alphanumeric?, non_ascii(r)
          found = true
          self.next
        when '\\'
          found = true
          self.next
          skip_escape
        else
          return found
        end
      end
    end
  end
end
