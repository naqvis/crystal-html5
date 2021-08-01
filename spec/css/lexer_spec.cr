require "./spec_helper"

module CSS
  it "Test Lexer next" do
    l = Lexer.new("hello ")
    backup = Proc(Char).new { l.backup; ' ' }
    tests = [
      {Proc(Char).new { l.peek }, 'h'},
      {Proc(Char).new { l.next }, 'h'},
      {Proc(Char).new { l.next }, 'e'},
      {backup, ' '},
      {Proc(Char).new { l.peek }, 'e'},
      {Proc(Char).new { l.next }, 'e'},
      {Proc(Char).new { l.next }, 'l'},
      {Proc(Char).new { l.next }, 'l'},
      {Proc(Char).new { l.next }, 'o'},
      {backup, ' '},
      {backup, ' '},
      {Proc(Char).new { l.next }, 'l'},
      {Proc(Char).new { l.next }, 'o'},
      {Proc(Char).new { l.peek }, ' '},
      {Proc(Char).new { l.next }, ' '},
      {Proc(Char).new { l.next }, EOF},
      {Proc(Char).new { l.next }, EOF},
      {Proc(Char).new { l.peek }, EOF},
    ]

    tests.each_with_index do |t, i|
      got = t[0].call
      fail "case=#{i}: expected: #{t[1]},got: #{got}" unless t[1] == got
    end
  end

  it "Test Lexer emit" do
    l = Lexer.new("hello world")
    tests = [
      {Proc(Nil).new {
        1.upto("hello".size) { |_| l.next }
      }, "hello"},
      {Proc(Nil).new { l.next }, " "},
      {Proc(Nil).new {
        loop do
          break if l.next == EOF
        end
      }, "world"},
    ]

    tests.each_with_index do |t, i|
      t[0].call
      l.emit(TokenType::Astr)
      tok = l.token
      fail "case=#{i}: expected: '#{t[1]}', got: '#{tok.val}'" unless t[1] == tok.val
    end
  end

  it "Test Lexer nonascii" do
    tests = [
      {' ', false},
      {'a', false},
      {EOF, false},
      {'世', true},
    ]
    l = Lexer.new(" ")
    tests.each_with_index do |t, i|
      got = l.non_ascii(t[0])
      fail "case=#{i}: expected: #{t[1]},got: #{got}" unless t[1] == got
    end
  end

  it "Test Lexer" do
    # raw_str = <<-RAW
    raw_str = %q('this is  \' a string ' "another string")
    # RAW
    tests = [
      {"7.3", [Token.new(TokenType::Number, "7.3", 0), Token.new(TokenType::EOF, "", 3)]},
      {"7.", [Token.new(TokenType::Number, "7", 0), Token.new(TokenType::Dot, ".", 1), Token.new(TokenType::EOF, "", 2)]},
      {"7 \t5n", [Token.new(TokenType::Number, "7", 0), Token.new(TokenType::Space, " \t", 1), Token.new(TokenType::Dimension, "5n", 3), Token.new(TokenType::EOF, "", 5)]},

      {"  ~", [
        Token.new(TokenType::Tilde, "  ~", 0), Token.new(TokenType::EOF, "", 3),
      ]},
      {"  ~=", [
        Token.new(TokenType::Space, "  ", 0), Token.new(TokenType::MatchIncludes, "~=", 2), Token.new(TokenType::EOF, "", 4),
      ]},
      {"lang", [
        Token.new(TokenType::Ident, "lang", 0), Token.new(TokenType::EOF, "", 4),
      ]},
      {"lang(", [
        Token.new(TokenType::Function, "lang(", 0), Token.new(TokenType::EOF, "", 5),
      ]},
      {"hi#name 43", [
        Token.new(TokenType::Ident, "hi", 0), Token.new(TokenType::Hash, "#name", 2), Token.new(TokenType::Space, " ", 7),
        Token.new(TokenType::Number, "43", 8), Token.new(TokenType::EOF, "", 10),
      ]},
      {raw_str, [
        Token.new(TokenType::String, "'this is  \\' a string '", 0), Token.new(TokenType::Space, " ", 23),
        Token.new(TokenType::String, "\"another string\"", 24), Token.new(TokenType::EOF, "", 40),
      ]},
      {"::foo(", [
        Token.new(TokenType::Colon, ":", 0), Token.new(TokenType::Colon, ":", 1), Token.new(TokenType::Function, "foo(", 2),
        Token.new(TokenType::EOF, "", 6),
      ]},
      {":not(#h2", [
        Token.new(TokenType::Not, ":not(", 0), Token.new(TokenType::Hash, "#h2", 5), Token.new(TokenType::EOF, "", 8),
      ]},
      {":not#h2", [
        Token.new(TokenType::Colon, ":", 0), Token.new(TokenType::Ident, "not", 1), Token.new(TokenType::Hash, "#h2", 4),
        Token.new(TokenType::EOF, "", 7),
      ]},
      {"a[href^='https://']", [
        Token.new(TokenType::Ident, "a", 0), Token.new(TokenType::LeftBrace, "[", 1), Token.new(TokenType::Ident, "href", 2),
        Token.new(TokenType::MatchPrefix, "^=", 6), Token.new(TokenType::String, "'https://'", 8),
        Token.new(TokenType::RightBrace, "]", 18), Token.new(TokenType::EOF, "", 19),
      ]},
      {"h2~a", [
        Token.new(TokenType::Ident, "h2", 0), Token.new(TokenType::Tilde, "~", 2), Token.new(TokenType::Ident, "a", 3),
        Token.new(TokenType::EOF, "", 4),
      ]},
      {"p ~ span", [
        Token.new(TokenType::Ident, "p", 0), Token.new(TokenType::Tilde, " ~", 1), Token.new(TokenType::Space, " ", 3),
        Token.new(TokenType::Ident, "span", 4), Token.new(TokenType::EOF, "", 8),
      ]},
      {"span > p, p", [
        Token.new(TokenType::Ident, "span", 0), Token.new(TokenType::Greater, " >", 4), Token.new(TokenType::Space, " ", 6),
        Token.new(TokenType::Ident, "p", 7), Token.new(TokenType::Comma, ",", 8), Token.new(TokenType::Space, " ", 9),
        Token.new(TokenType::Ident, "p", 10), Token.new(TokenType::EOF, "", 11),
      ]},
      {"span > p p", [
        Token.new(TokenType::Ident, "span", 0), Token.new(TokenType::Greater, " >", 4), Token.new(TokenType::Space, " ", 6),
        Token.new(TokenType::Ident, "p", 7), Token.new(TokenType::Space, " ", 8),
        Token.new(TokenType::Ident, "p", 9), Token.new(TokenType::EOF, "", 10),
      ]},
      {"-2n-1", [
        Token.new(TokenType::Dimension, "-2n-1", 0), Token.new(TokenType::EOF, "", 5),
      ]},

    ]

    tests.each_with_index do |t, i|
      l = Lexer.new(t[0])
      spawn { l.parse_next }
      tokens = [] of Token
      loop do
        tok = l.token
        tokens << tok
        break if tok.type.error? || tok.type.eof?
      end
      fail "case=#{i}:'#{t[0]}' wanted: #{t[1].size} tokens, got: #{tokens.size}" unless t[1].size == tokens.size
      tokens.should eq(t[1])
    end
  end
end
