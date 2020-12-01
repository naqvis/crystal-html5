require "./spec_helper"

module CSS
  it "Test Compile" do
    html = "<div><p>foo</p><span><p>bar</p></span></div>"
    expr = "span > p, p"
    want = ["<p>bar</p>", "<p>foo</p>", "<p>bar</p>"]

    sel = compile(expr)
    run_test(1, html, sel, want)
  end

  it "Test Compile Error" do
    tests = [
      "",
      "*foo",
    ]

    tests.each do |t|
      expect_raises(SyntaxError) do
        compile(t)
      end
    end
  end

  it "Test Compile Selector" do
    tests = [
      {"<span>This is not red.</span>
			<p>Here is a paragraph.</p>
			<code>Here is some code.</code>
			<span>And here is a span.</span>
			<span>And another span.</span>
      ", "p ~ span", ["<span>And here is a span.</span>", "<span>And another span.</span>"]},
      {"<div><p>foo</p><span><p>bar</p></span></div>", "p", ["<p>foo</p>", "<p>bar</p>"]},
      {"<div><p>foo</p><span><p>bar</p></span></div>", "div > p", ["<p>foo</p>"]},
      {"<div><p>foo</p><span><p>bar</p></span></div>", "span > p", ["<p>bar</p>"]},
      {"<div><p>foo</p><span><p>bar</p></span></div>", "span p", ["<p>bar</p>"]},
      {"<div><p>foo</p><span><p>bar</p></span></div>", "div p", ["<p>foo</p>", "<p>bar</p>"]},
      {"<div><p>foo</p><span><p>bar</p></span></div>", "div div", [] of String},
      {"<div><p>foo</p><span><p>bar</p></span></div>", "div *", ["<p>foo</p>", "<span><p>bar</p></span>"]},
      {"<div><p class=\"hi\">foo</p><span><p class=\"hi\">bar</p></span></div>", "div .hi", [
        "<p class=\"hi\">foo</p>", "<p class=\"hi\">bar</p>",
      ]},
      {"<p><a id=\"foo\"></a></p>", "p :empty", ["<a id=\"foo\"></a>"]},
      {"<div><p><a id=\"foo\"></a></p></div>", "div > p a", ["<a id=\"foo\"></a>"]},
    ]

    tests.each_with_index do |t, i|
      l = Lexer.new(t[1])
      spawn { l.parse_next }
      c = Compiler.new(l)
      sel = c.compile_selector
      fail "case=#{i}: did not parse entire input" unless c.peek.type == TokenType::EOF
      run_test(i, t[0], sel, t[2])
    end
  end

  it "Test Compile Simple Selector Seq" do
    tests = [
      {"<p><a></a></p>", "a", ["<a></a>"]},
      {"<p><a class=\"foo\"></a></p>", "a.foo", ["<a class=\"foo\"></a>"]},
      {"<p><a></a></p>", "a.foo", [] of String},
      {"<p><a id=\"foo\"></a></p>", "a#foo", ["<a id=\"foo\"></a>"]},
      {"<p><a id=\"foo\"></a></p>", "#foo", ["<a id=\"foo\"></a>"]},
      {"<p><a id=\"foo\"></a></p>", "a[id=foo]", ["<a id=\"foo\"></a>"]},
      {"<p><a id=\"foo\"></a></p>", "p:empty", [] of String},
      {"<p><a id=\"1\"></a><a id=\"2\"></a><a id=\"3\"></a><a id=\"4\"></a></p>", "a:nth-child(odd)",
       ["<a id=\"1\"></a>", "<a id=\"3\"></a>"]},
    ]

    tests.each_with_index do |t, i|
      l = Lexer.new(t[1])
      spawn { l.parse_next }
      c = Compiler.new(l)
      sel = c.compile_selector
      fail "case=#{i}: did not parse entire input" unless c.peek.type == TokenType::EOF
      run_test(i, t[0], sel, t[2])
    end
  end

  it "Test Compile Attribute" do
    tests = [
      {
        "<p><a id=\"foo\"></a></p>",
        "[id=foo]",
        ["<a id=\"foo\"></a>"],
      },
      {
        "<p><a id=\"foo\"></a></p>",
        "[id = 'foo']",
        ["<a id=\"foo\"></a>"],
      },
      {
        "<p><a id=\"foo\"></a></p>",
        "[id=\"foo\"]",
        ["<a id=\"foo\"></a>"],
      },
      {
        "<p><a id=\"hello-world\"></a><a id=\"helloworld\"></a></p>",
        "[id|=\"hello\"]",
        ["<a id=\"hello-world\"></a>"],
      },
      {
        "<p><a id=\"hello-world\"></a><a id=\"worldhello\"></a></p>",
        "[id^=\"hello\"]",
        ["<a id=\"hello-world\"></a>"],
      },
      {
        "<p><a id=\"hello-world\"></a><a id=\"worldhello\"></a></p>",
        "[id$=\"hello\"]",
        ["<a id=\"worldhello\"></a>"],
      },
      {
        "<p><a id=\"hello-world\"></a><a id=\"worldhello\"></a></p>",
        "[id*=\"hello\"]",
        ["<a id=\"hello-world\"></a>", "<a id=\"worldhello\"></a>"],
      },
      {
        "<p><a id=\"hello world\"></a><a id=\"hello-world\"></a></p>",
        "[id~=\"hello\"]",
        ["<a id=\"hello world\"></a>"],
      },
    ]

    tests.each_with_index do |t, i|
      l = Lexer.new(t[1])
      spawn { l.parse_next }
      c = Compiler.new(l)
      m = c.compile_attr
      sel = SelectorSequence.new([m.as(Matcher)])
      fail "case=#{i}: did not parse entire input" unless c.peek.type == TokenType::EOF
      run_test(i, t[0], sel, t[2])
    end
  end

  it "Test Parse Nth Argument" do
    tests = [
      {"even", 2, 0},
      {"odd", 2, 1},
      {"2n+1", 2, 1},
      {"-2n-1", -2, -1},
      {"2n", 2, 0},
      {"+2n", 2, 0},
      {"-2n", -2, 0},
      {"4", 0, 4},
      {"4n - 3", 4, -3},
    ]

    tests.each_with_index do |t, i|
      l = Lexer.new(t[0])
      spawn { l.parse_next }
      c = Compiler.new(l)
      a, b = c.parse_nth_args
      fail "case=#{i}: did not parse entire input" unless c.peek.type == TokenType::EOF
      fail "case='#{t[0]}': wanted=(a=#{t[1]}, b=#{t[2]}), got=(a=#{a}, b=#{b})" unless t[1] == a && t[2] == b
    end
  end

  it "Test Parse Nth" do
    tests = [
      {"9n", 9, 0, false, true},
      {"-2n+2", -2, 2, true, true},
      {"91n3n", 0, 0, false, false},
    ]

    tests.each_with_index do |t, i|
      unless t[4]
        expect_raises(SyntaxError) do
          a, b, found = parse_nth(t[0])
        end
      else
        a, b, found = parse_nth(t[0])
      end
      if t[4]
        fail "case=#{t[0]}: want (a=#{t[1]}), got (a=#{a})" unless t[1] == a
        fail "case=#{t[0]}: want (found=#{t[3]}), got (found=#{found})" unless t[3] == found
        fail "case=#{t[0]}: want (b=#{t[2]}), got (a=#{b})" unless t[2] == b
      end
    end
  end

  it "Test NthRegular Expression" do
    nth_regex = /^([-+]?[\d]+)n([-+]?[\d]+)?$/
    tests = [
      {"-2n-2", "-2", "-2", true},
      {"-2n+2", "-2", "+2", true},
      {"-80n+100", "-80", "+100", true},
      {"+80n+100", "+80", "+100", true},
      {"80n+100", "80", "+100", true},
      {" 80n+100 ", "", "", false},
      {"80n+100 ", "", "", false},
      {" 80n+100", "", "", false},
      {"-23n", "-23", "", true},
      {"foobar", "", "", false},
    ]

    tests.each_with_index do |t, i|
      submatch = nth_regex.match(t[0])
      fail "case=#{t[0]}: failed to parse" if t[3] && (submatch.nil? || submatch.try &.size != 3)
      fail "case=#{t[0]}: expected to fail to parse, but it didn't fail" if !t[3] && !submatch.nil?
      if t[3]
        matches = submatch.not_nil!.to_a
        fail "case=#{t[0]}: expected a=#{t[1]}, got a=#{matches[1]}" unless t[1] == matches[1] || ""
        fail "case=#{t[0]}: expected b=#{t[2]}, got b=#{matches[2]}" unless t[2] == matches[2] || ""
      end
    end
  end
end
