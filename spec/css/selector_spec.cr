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
      "<p>bar</p>",
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
                                                                    NthChildPseudo.new(0, 1).as(Matcher)]},
      {html, ["<div class=\"box\"><!-- I will be selected --></div>"], [AttrMatcher.new("class", "box").as(Matcher),
                                                                        MatcherFunc.new(->empty(HTML5::Node))]},
    ]

    tests.each_with_index do |t, i|
      run_test(i, t[0], SelectorSequence.new(t[2]), t[1])
    end
  end

  it "Test :scope MDN example" do
    # Exact HTML from MDN documentation
    html = %q(
      <div id="context">
        <div id="element-1">
          <div id="element-1-1"></div>
          <div id="element-1-2"></div>
        </div>
        <div id="element-2">
          <div id="element-2-1"></div>
        </div>
      </div>
    )

    # Parse and get context element (equivalent to document.getElementById("context"))
    doc = HTML5.parse(html)
    context = doc.css("#context").first

    # Execute equivalent of: context.querySelectorAll(":scope > div")
    selected = context.css(":scope > div")

    # Verify we get element-1 and element-2 (direct children only)
    result_ids = selected.map { |el| el["id"]?.try(&.val) || "" }
    expected_ids = ["element-1", "element-2"]

    fail "Expected IDs: #{expected_ids}, got: #{result_ids}" unless result_ids == expected_ids

    # Additional test: verify :scope matches context itself
    scope_match = context.css(":scope")
    fail "Expected 1 :scope match, got #{scope_match.size}" unless scope_match.size == 1
    fail "Expected :scope to match context element" unless scope_match.first == context

    # Test that nested elements are NOT selected by :scope > div
    all_divs = context.css("div")
    direct_children = context.css(":scope > div")

    # Should have more total divs than direct children
    fail "Should have more total divs (#{all_divs.size}) than direct children (#{direct_children.size})" unless all_divs.size > direct_children.size

    # Verify nested elements exist but are not in direct children
    nested_element = doc.css("#element-1-1").first
    fail "Nested element should not be in direct children" if direct_children.includes?(nested_element)
  end
end
