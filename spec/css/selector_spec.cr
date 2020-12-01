require "./spec_helper"

module CSS
  it "Test Selector" do
    html = <<-HTML
      <span>This is not red.</span>
			<p>Here is a paragraph.</p>
			<code>Here is some code.</code>
			<span>And here is a span.</span>
      <span>And another span.</span>
  HTML

    want = [
      "<span>And here is a span.</span>",
      "<span>And another span.</span>",
    ]

    selector = SelectorImpl.new(
      SelectorSequence.new([TypeSelector.new("p").as(Matcher)]),
      [CombinatorSelector.new(
        TokenType::Tilde,
        SelectorSequence.new([TypeSelector.new("span").as(Matcher)])
      )]
    )

    run_test(1, html, selector, want)
  end

  it "Test Selector 2" do
    html = <<-HTML
    <div><p>foo</p><span><p>bar</p></span></div>
  HTML

    want = [
      "<p>foo</p>",
      "<span><p>bar</p></span>",
    ]

    selector = SelectorImpl.new(
      SelectorSequence.new([TypeSelector.new("div").as(Matcher)]),
      [CombinatorSelector.new(
        TokenType::Space,
        SelectorSequence.new([Universal.new.as(Matcher)])
      )]
    )

    run_test(2, html, selector, want)
  end

  it "Test Matcher" do
    html = <<-HTML
    <div class="box"><!-- I will be selected --></div>
			<div class="box">I will be not be selected</div>
			<div class="box">
			    <!-- I will not be selected because of the whitespace around this comment -->
      </div>
HTML
    tests = [
      {"<p><a id=\"foo\"></a></p>", ["<a id=\"foo\"></a>"], [AttrMatcher.new("id", "foo").as(Matcher)]},
      {"<p><a id=\"bar\"></a></p>", [] of String, [AttrMatcher.new("id", "foo").as(Matcher)]},
      {"<p><a class=\"bar\"></a></p>", ["<a class=\"bar\"></a>"], [AttrMatcher.new("class", "bar").as(Matcher)]},
      {"<p><a id=\"foo\"></a><a></a></p>", ["<a id=\"foo\"></a>", "<a></a>"], [TypeSelector.new("a").as(Matcher)]},
      # non-standard HTML
      {"<p><foobar></foobar></p>", ["<foobar></foobar>"], [TypeSelector.new("foobar").as(Matcher)]},
      {"<p><a id=\"foo\"></a><a></a></p>", ["<a id=\"foo\"></a>"], [TypeSelector.new("a").as(Matcher),
                                                                    MatcherFunc.new(->first_child(HTML5::Node))]},
      {html, ["<div class=\"box\"><!-- I will be selected --></div>"], [AttrMatcher.new("class", "box").as(Matcher),
                                                                        MatcherFunc.new(->empty(HTML5::Node))]},
    ]

    tests.each_with_index do |t, i|
      run_test(i, t[0], SelectorSequence.new(t[2]), t[1])
    end
  end

  it "Test Post Matches" do
    tests = [
      {2, 4, 3, true},
      {2, 4, 5, true},
      {2, 4, 13, true},
      {-2, 7, 0, true},
      {-2, 7, 6, true},
      {-2, 7, 7, false},
      {0, 7, 6, true},
    ]

    tests.each_with_index do |t, i|
      got = post_matches(t[0], t[1], t[2])
      fail "case=#{i} (a=#{t[0]}, b=#{t[1]}, pos=#{t[2]}): want=#{t[3]}, got=#{got}" unless got == t[3]
    end
  end
end
