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
      {"<div><p>foo</p><span><p>bar</p></span></div>", "div *", ["<p>foo</p>", "<span><p>bar</p></span>", "<p>bar</p>"]},
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
      fail "case=#{i}: did not parse entire input" unless c.peek.type.eof?
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
      fail "case=#{i}: did not parse entire input" unless c.peek.type.eof?
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
      c.next
      fail "case=#{i}: did not parse entire input. token: #{c.peek}" unless c.peek.type.eof?
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
      pp "testing '#{t[0]}'"
      l = Lexer.new(t[0])
      spawn { l.parse_next }
      c = Compiler.new(l)
      a, b = c.parse_nth_args
      fail "case=#{i}: did not parse entire input. token: #{c.peek}" unless c.peek.type.eof?
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

  it "extensive selector test" do
    tests = [
      {
        %q(<body><address>This address...</address></body>),
        "address",
        [
          "<address>This address...</address>",
        ],
      },
      {
        %q(<!-- comment --><html><head></head><body>text</body></html>),
        "*",
        [
          "<html><head></head><body>text</body></html>",
          "<head></head>",
          "<body>text</body>",
        ],
      },
      {
        %q(<html><head></head><body></body></html>),
        "*",
        [
          "<html><head></head><body></body></html>",
          "<head></head>",
          "<body></body>",
        ],
      },
      {
        %q(<p id="foo"><p id="bar">),
        "#foo",
        [
          %q(<p id="foo"></p>),
        ],
      },
      {
        %q(<ul><li id="t1"><p id="t1">),
        "li#t1",
        [
          %q(<li id="t1"><p id="t1"></p></li>),
        ],
      },
      {
        %q(<ol><li id="t4"><li id="t44">),
        "*#t4",
        [
          %q(<li id="t4"></li>),
        ],
      },
      {
        %q(<ul><li class="t1"><li class="t2">),
        ".t1",
        [
          %q(<li class="t1"></li>),
        ],
      },
      {
        %q(<p class="t1 t2">),
        "p.t1",
        [
          %q(<p class="t1 t2"></p>),
        ],
      },
      {
        %q(<div class="test">),
        "div.teST",
        [] of String,
      },
      {
        %q(<p class="t1 t2">),
        ".t1.fail",
        [] of String,
      },
      {
        %q(<p class="t1 t2">),
        "p.t1.t2",
        [
          %q(<p class="t1 t2"></p>),
        ],
      },
      {
        %q(<p><p title="title">),
        "p[title]",
        [
          %q(<p title="title"></p>),
        ],
      },
      {
        %q(<address><address title="foo"><address title="bar">),
        %q(address[title="foo"]),
        [
          %q(<address title="foo"><address title="bar"></address></address>),
        ],
      },
      {
        %q(<p title="tot foo bar">),
        %q([    	title        ~=       foo    ]),
        [
          %q(<p title="tot foo bar"></p>),
        ],
      },
      {
        %q(<p title="hello world">),
        %q([title~="hello world"]),
        [] of String,
      },
      {
        %q(<p lang="en"><p lang="en-gb"><p lang="enough"><p lang="fr-en">),
        %q([lang|="en"]),
        [
          %q(<p lang="en"></p>),
          %q(<p lang="en-gb"></p>),
        ],
      },
      {
        %q(<p title="foobar"><p title="barfoo">),
        %q([title^="foo"]),
        [
          %q(<p title="foobar"></p>),
        ],
      },
      {
        %q(<p title="foobar"><p title="barfoo">),
        %q([title$="bar"]),
        [
          %q(<p title="foobar"></p>),
        ],
      },
      {
        %q(<p title="foobarufoo">),
        %q([title*="bar"]),
        [
          %q(<p title="foobarufoo"></p>),
        ],
      },
      {
        %q(<p class=" ">This text should be green.</p><p>This text should be green.</p>),
        %q(p[class$=" "]),
        [] of String,
      },
      {
        %q(<p class="">This text should be green.</p><p>This text should be green.</p>),
        %q(p[class$=""]),
        [] of String,
      },
      {
        %q(<p class=" ">This text should be green.</p><p>This text should be green.</p>),
        %q([class^=" "]),
        [] of String,
      },
      {
        %q(<p class="">This text should be green.</p><p>This text should be green.</p>),
        %q([class^=""]),
        [] of String,
      },
      {
        %q(<p class=" ">This text should be green.</p><p>This text should be green.</p>),
        %q([class*=" "]),
        [] of String,
      },
      {
        %q(<p class="">This text should be green.</p><p>This text should be green.</p>),
        %q([class*=""]),
        [] of String,
      },
      {
        %q(<input type="radio" name="Sex" value="F"/>),
        %q(input[name=Sex][value=F]),
        [
          %q(<input type="radio" name="Sex" value="F"/>),
        ],
      },
      {
        %q(<table border="0" cellpadding="0" cellspacing="0" style="table-layout: fixed; width: 100%; border: 0 dashed; border-color: #FFFFFF"><tr style="height:64px">aaa</tr></table>),
        %q(table[border="0"][cellpadding="0"][cellspacing="0"]),
        [
          %q(<table border="0" cellpadding="0" cellspacing="0" style="table-layout: fixed; width: 100%; border: 0 dashed; border-color: #FFFFFF"><tbody><tr style="height:64px"></tr></tbody></table>),
        ],
      },
      {
        %q(<p class="t1 t2">),
        ".t1:not(.t2)",
        [] of String,
      },
      {
        %q(<div class="t3">),
        %q(div:not(.t1)),
        [
          %q(<div class="t3"></div>),
        ],
      },
      {
        %q(<div><div class="t2"><div class="t3">),
        %q(div:not([class="t2"])),
        [
          %q(<div><div class="t2"><div class="t3"></div></div></div>),
          %q(<div class="t3"></div>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3></ol>),
        %q(li:nth-child(odd)),
        [
          %q(<li id="1"></li>),
          %q(<li id="3"></li>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3></ol>),
        %q(li:nth-child(even)),
        [
          %q(<li id="2"></li>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3></ol>),
        %q(li:nth-child(-n+2)),
        [
          %q(<li id="1"></li>),
          %q(<li id="2"></li>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3></ol>),
        %q(li:nth-child(n+2)),
        [
          %q(<li id="2"></li>),
          %q(<li id="3"></li>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3></ol>),
        %q(li:nth-child(3n+1)),
        [
          %q(<li id="1"></li>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3><li id=4></ol>),
        %q(li:nth-last-child(odd)),
        [
          %q(<li id="2"></li>),
          %q(<li id="4"></li>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3><li id=4></ol>),
        %q(li:nth-last-child(even)),
        [
          %q(<li id="1"></li>),
          %q(<li id="3"></li>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3><li id=4></ol>),
        %q(li:nth-last-child(-n+2)),
        [
          %q(<li id="3"></li>),
          %q(<li id="4"></li>),
        ],
      },
      {
        %q(<ol><li id=1><li id=2><li id=3><li id=4></ol>),
        %q(li:nth-last-child(3n+1)),
        [
          %q(<li id="1"></li>),
          %q(<li id="4"></li>),
        ],
      },
      {
        %q(<p>some text <span id="1">and a span</span><span id="2"> and another</span></p>),
        %q(span:first-child),
        [
          %q(<span id="1">and a span</span>),
        ],
      },
      {
        %q(<span>a span</span> and some text),
        %q(span:last-child),
        [
          %q(<span>a span</span>),
        ],
      },
      {
        %q(<address></address><p id=1><p id=2>),
        %q(p:nth-of-type(2)),
        [
          %q(<p id="2"></p>),
        ],
      },
      {
        %q(<address></address><p id=1><p id=2></p><a>),
        %q(p:nth-last-of-type(2)),
        [%q(<p id="1"></p>)],
      },
      {
        %q(<address></address><p id=1><p id=2></p><a>),
        %q(p:last-of-type),
        [
          %q(<p id="2"></p>),
        ],
      },
      {
        %q(<address></address><p id=1><p id=2></p><a>),
        %q(p:first-of-type),
        [
          %q(<p id="1"></p>),
        ],
      },
      {
        %q(<div><p id="1"></p><a></a></div><div><p id="2"></p></div>),
        %q(p:only-child),
        [
          %q(<p id="2"></p>),
        ],
      },
      {
        %q(<div><p id="1"></p><a></a></div><div><p id="2"></p><p id="3"></p></div>),
        %q(p:only-of-type),
        [
          %q(<p id="1"></p>),
        ],
      },
      {
        %q(<p id="1"><!-- --><p id="2">Hello<p id="3"><span>),
        %q(:empty),
        [
          %q(<head></head>),
          %q(<p id="1"><!-- --></p>),
          %q(<span></span>),
        ],
      },
      {
        %q(<div><p id="1"><table><tr><td><p id="2"></table></div><p id="3">),
        %q(div p),
        [
          %q(<p id="1"><table><tbody><tr><td><p id="2"></p></td></tr></tbody></table></p>),
          %q(<p id="2"></p>),
        ],
      },
      {
        %q(<div><p id="1"><table><tr><td><p id="2"></table></div><p id="3">),
        %q(div table p),
        [
          %q(<p id="2"></p>),
        ],
      },
      {
        %q(<div><p id="1"><div><p id="2"></div><table><tr><td><p id="3"></table></div>),
        %q(div > p),
        [
          %q(<p id="1"></p>),
          %q(<p id="2"></p>),
        ],
      },
      {
        %q(<p id="1"><p id="2"></p><address></address><p id="3">),
        %q(p ~ p),
        [
          %q(<p id="2"></p>),
          %q(<p id="3"></p>),
        ],
      },
      {
        %q(<p id="1"></p>
         <!--comment-->
         <p id="2"></p><address></address><p id="3">),
        %q(p + p),
        [
          %q(<p id="2"></p>),
        ],
      },
      {
        %q(<ul><li></li><li></li></ul><p>),
        %q(li, p),
        [
          "<li></li>",
          "<li></li>",
          "<p></p>",
        ],
      },
      {
        %q(<p id="1"><p id="2"></p><address></address><p id="3">),
        %q(p +/*This is a comment*/ p),
        [
          %q(<p id="2"></p>),
        ],
      },
      {
        %q(<p>Text block that <span>wraps inner text</span> and continues</p>),
        %q(p:contains("that wraps")),
        [
          %q(<p>Text block that <span>wraps inner text</span> and continues</p>),
        ],
      },
      {
        %q(<p>Text block that <span>wraps inner text</span> and continues</p>),
        %q(p:containsOwn("that wraps")),
        [] of String,
      },
      {
        %q(<p>Text block that <span>wraps inner text</span> and continues</p>),
        %q(:containsOwn("inner")),
        [
          %q(<span>wraps inner text</span>),
        ],
      },
      {
        %q(<p>Text block that <span>wraps inner text</span> and continues</p>),
        %q(p:containsOwn("block")),
        [
          %q(<p>Text block that <span>wraps inner text</span> and continues</p>),
        ],
      },
      {
        %q(<form>
          <label>Username <input type="text" name="username" /></label>
          <label>Password <input type="password" name="password" /></label>
          <label>Country
            <select name="country">
              <option value="ca">Canada</option>
              <option value="us">United States</option>
            </select>
          </label>
          <label>Bio <textarea name="bio"></textarea></label>
          <button>Sign up</button>
        </form>),
        %q(:input),
        [
          %q(<input type="text" name="username"/>),
          %q(<input type="password" name="password"/>),
          %q(<select name="country">
              <option value="ca">Canada</option>
              <option value="us">United States</option>
            </select>),
          %q(<textarea name="bio"></textarea>),
          %q(<button>Sign up</button>),
        ],
      },
      {
        %q(<html><head></head><body></body></html>),
        ":root",
        [
          "<html><head></head><body></body></html>",
        ],
      },
      {
        %q(<html><head></head><body></body></html>),
        "*:root",
        [
          "<html><head></head><body></body></html>",
        ],
      },
      {
        %q(<html><head></head><body></body></html>),
        "*:root:first-child",
        [] of String,
      },
      {
        %q(<html><head></head><body></body></html>),
        "*:root:nth-child(1)",
        [] of String,
      },

      {
        %q(<html><head></head><body><p></p><div></div><span></span><a></a><form></form></body></html>),
        "body > *:nth-child(3n+2)",
        [
          "<div></div>",
          "<form></form>",
        ],
      },
    ]

    tests.each_with_index do |t, i|
      pp "Testing - #{t[1]}"
      sel = compile(t[1])
      run_test(i, t[0], sel, t[2])
    end
  end
end
