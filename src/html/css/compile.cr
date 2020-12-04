module CSS
  def self.compile(expr : String) : Selector
    lexer = Lexer.new(expr)
    spawn { lexer.parse_next }
    selectors = Compiler.new(lexer).compile_selectors_group
    Selector.new(selectors)
  end

  private record SyntaxErr, msg : String, offset : Int32 do
    def error
      @msg
    end

    def exception
      SyntaxError.new(@msg)
    end
  end

  private struct Compiler
    def initialize(@t : TokenEmitter, @first_peek : Bool, @peek_tok : Token)
    end

    def self.new(t : TokenEmitter, first_peek : Bool = true)
      new(t, first_peek, Token.new(TokenType::EOF, "", 0))
    end

    def peek
      if @first_peek
        @first_peek = false
        @peek_tok = @t.token
      end
      @peek_tok
    end

    def next
      tok = self.peek
      return tok if [TokenType::Error, TokenType::EOF].includes?(tok.type)
      @peek_tok = @t.token
      tok
    end

    def skip_space
      while (self.peek.type == TokenType::Space)
        self.next
      end
      self.peek
    end

    def compile_selectors_group
      sel = compile_selector
      selectors = [sel]
      loop do
        t = self.next
        case t.type
        when .eof? then return selectors
        when .comma?
          self.skip_space
          selectors << compile_selector
        else
          raise CSS.syntax_error(t, TokenType::EOF, TokenType::Comma).exception
        end
      end
    end

    def compile_selector
      sel = SelectorImpl.new(compile_simple_selector_seq())
      combination = false
      loop do
        t = self.peek
        case t.type
        when .plus?, .greater?, .tilde?, .space?
          self.next
          self.skip_space
          combination = true
          sel.combs << CombinatorSelector.new(t.type, compile_simple_selector_seq)
        when .ident?
          return sel unless combination
          combination = false
          sel.combs << CombinatorSelector.new(t.type, compile_simple_selector_seq)
        when .eof?, .comma?
          return sel.as(Select)
        else
          raise CSSException.new("Unhandled compiler selector #{t.type}")
        end
        self.skip_space
      end
    end

    def compile_simple_selector_seq
      matchers = [] of Matcher
      first_loop = true
      loop do
        t = self.peek
        case t.type
        when .ident?
          return SelectorSequence.new(matchers) unless first_loop
          matchers = [TypeSelector.new(t.val).as(Matcher)]
        when .astr?
          return SelectorSequence.new(matchers) unless first_loop
          matchers = [Universal.new.as(Matcher)]
        when .dot?
          self.next
          tk = self.peek
          raise CSS.syntax_error(tk, TokenType::Ident).exception unless tk.type == TokenType::Ident
          matchers = [AttrMatcher.new("class", tk.val).as(Matcher)]
        when .hash?
          matchers = [AttrMatcher.new("id", t.val.lchop("#")).as(Matcher)]
        when .left_brace?
          matchers << compile_attr()
        when .colon?
          matchers << compile_pseudo()
        else
          raise CSS.syntax_error(t, TokenType::Ident, TokenType::Dot, TokenType::Hash).exception if first_loop
          return SelectorSequence.new(matchers)
        end
        self.next
        first_loop = false
      end
    end

    def compile_attr
      tok = self.next
      raise CSS.syntax_error(tok, TokenType::LeftBrace).exception unless tok.type == TokenType::LeftBrace

      self.skip_space
      tok = self.next
      raise CSS.syntax_error(tok, TokenType::Ident).exception unless tok.type == TokenType::Ident

      key = tok.val
      self.skip_space

      tok = self.next
      matcher_type = case tok.type
                     when .match?, .match_dash?, .match_includes?, .match_prefix?, .match_sub_str?, .match_suffix?
                       tok.type
                     when .right_brace?
                       return AttrSelector.new(tok.val)
                     else
                       raise CSS.syntax_error(tok, TokenType::RightBrace).exception
                     end

      self.skip_space
      val = ""
      tok = self.next
      case tok.type
      when .ident?
        val = tok.val
      when .string?
        val = tok.val[1...tok.val.size - 1] if tok.val.size > 2 # string correctness is guranteed by lexer
      else
        raise CSS.syntax_error(tok, TokenType::Ident, TokenType::String).exception
      end

      self.skip_space
      t = self.next
      raise CSS.syntax_error(t, TokenType::RightBrace).exception unless t.type == TokenType::RightBrace

      case matcher_type
      when .match_dash?
        AttrCompMatcher.new(key, val, ->CSS.dash_matcher(String, String))
      when .match_includes?
        AttrCompMatcher.new(key, val, ->CSS.includes_matcher(String, String))
      when .match_prefix?
        AttrCompMatcher.new(key, val, ->(s : String, m : String) { s.starts_with?(m) })
      when .match_sub_str?
        AttrCompMatcher.new(key, val, ->(s : String, m : String) { s.includes?(m) })
      when .match_suffix?
        AttrCompMatcher.new(key, val, ->(s : String, m : String) { s.ends_with?(m) })
      else
        AttrMatcher.new(key, val)
      end
    end

    def compile_pseudo
      tok = self.next
      raise CSS.syntax_error(tok, TokenType::Colon).exception unless tok.type == TokenType::Colon

      double_colon = self.peek.type == TokenType::Colon
      self.next if double_colon

      t = self.next
      case t.type
      when .ident?
        unless double_colon
          case t.val
          when "empty"         then return MatcherFunc.new(->CSS.empty(HTML5::Node))
          when "first-child"   then return MatcherFunc.new(->CSS.first_child(HTML5::Node))
          when "first-of-type" then return MatcherFunc.new(->CSS.first_of_type(HTML5::Node))
          when "last-child"    then return MatcherFunc.new(->CSS.last_child(HTML5::Node))
          when "last-of-type"  then return MatcherFunc.new(->CSS.last_of_type(HTML5::Node))
          when "only-child"    then return MatcherFunc.new(->CSS.only_child(HTML5::Node))
          when "only-of-type"  then return MatcherFunc.new(->CSS.only_of_type(HTML5::Node))
          when "root"          then return MatcherFunc.new(->CSS.root(HTML5::Node))
          else
            raise CSSException.new("Unsupported pseudo type : #{t.val}")
          end
        end
        s = ":"
        s = "::" if double_colon
        raise SyntaxErr.new("uknown psuedo: #{s + t.val}", t.start).exception
      when .function?
        raise SyntaxErr.new("uknown psuedo: #{t.val}", t.start).exception if double_colon
        if t.val == "nth-child("
          a, b = parse_nth_args()
          m = NthChild.new(a, b)
        else
          raise SyntaxErr.new("uknown psuedo: #{t.val}", t.start).exception
        end
        raise CSS.syntax_error(self.next, TokenType::RightParen).exception unless self.peek.type == TokenType::RightParen
        self.next
        return m.not_nil!
      else
        raise CSS.syntax_error(t, TokenType::Ident, TokenType::Function).exception
      end
    end

    def parse_nth_args
      minus = false
      a, b = 0, 0
      self.skip_space
      t = self.peek
      case t.type
      when .ident?
        self.next
        case t.val
        when "even"
          return {2, 0}
        when "odd"
          return {2, 1}
        else
          raise CSSException.new("Unsupported argument : #{t.val}")
        end
      when .number?
        self.next
        begin
          return {0, t.val.to_i}
        rescue ex
          raise SyntaxErr.new(ex.message.not_nil!, t.start).exception
        end
      when .sub?
        self.next
        minus = true
      when .plus?
        self.next
      when .dimension?
        #
      else
        raise CSS.syntax_error(t, TokenType::Ident, TokenType::Number, TokenType::Sub, TokenType::Plus).exception
      end

      self.skip_space
      t = self.next
      case t.type
      when .dimension?
        a, b, found = CSS.parse_nth(t.val)
        a = 0 - a if minus
        return {a, b} if found
        b = 0
      when .number?
        begin
          b = t.val.to_i
        rescue ex
          raise SyntaxErr.new(ex.message.not_nil!, t.start).exception
        end
        b = 0 - b if minus
        self.skip_space
        return {a, b}
      else
        raise CSS.syntax_error(t, TokenType::Ident, TokenType::Number, TokenType::Sub, TokenType::Plus).exception
      end

      self.skip_space
      case self.peek.type
      when .sub?
        minus = true
      when .plus?
        minus = false
      else
        return {a, b}
      end

      self.next
      self.skip_space
      t = self.next
      raise CSS.syntax_error(t, TokenType::Ident, TokenType::Number, TokenType::Sub, TokenType::Plus).exception unless t.type == TokenType::Number
      begin
        b = t.val.to_i
      rescue ex
        raise SyntaxErr.new(ex.message.not_nil!, t.start).exception
      end
      b = 0 - b if minus
      self.skip_space
      return {a, b}
    end
  end

  protected def self.lex_error(t : Token) : SyntaxErr
    SyntaxErr.new(t.val, t.start)
  end

  protected def self.syntax_error(t : Token, *exp : TokenType) : SyntaxErr
    SyntaxErr.new("expected #{exp}, got #{t.type} \"#{t.val}\"", t.start)
  end

  private Nth_Regex = /^([-+]?[\d]+)n([-+]?[\d]+)?$/

  protected def self.parse_nth(s : String)
    a, b = 0, 0
    submatch = Nth_Regex.match(s)
    if submatch.nil? || submatch.try &.size != 3
      raise SyntaxError.new("string is not of form {number}n or {number}n{number}")
    end
    matches = submatch.not_nil!.to_a
    begin
      a = matches[1].not_nil!.to_i
    rescue
      raise SyntaxError.new("string is not of form {number}n or {number}n{number}")
    end
    found = matches[2] != nil
    return {a, b, found} unless found
    begin
      b = matches[2].not_nil!.to_i
    rescue
      raise CSSException.new("string is not of form {number}n or {number}n{number}")
    end
    {a, b, found}
  end
end
