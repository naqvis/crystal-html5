require "./spec_helper"

module HTML5
  record UnescapeTest, desc : String, html : String, unescaped : String

  UNESCAPE_TESTS = [
    # Handle no entities.
    UnescapeTest.new(
      "copy",
      "A\ttext\nstring",
      "A\ttext\nstring",
    ),
    # Handle simple named entities.
    UnescapeTest.new(
      "simple",
      "&amp; &gt; &lt;",
      "& > <",
    ),
    # Handle hitting the end of the string.
    UnescapeTest.new(
      "stringEnd",
      "&amp &amp",
      "& &",
    ),
    # Handle entities with two codepoints.
    UnescapeTest.new(
      "multiCodepoint",
      "text &gesl; blah",
      "text \u22db\ufe00 blah",
    ),
    # Handle decimal numeric entities.
    UnescapeTest.new(
      "decimalEntity",
      "Delta = &#916; ",
      "Delta = Δ ",
    ),
    # Handle hexadecimal numeric entities.
    UnescapeTest.new(
      "hexadecimalEntity",
      "Lambda = &#x3bb; = &#X3Bb ",
      "Lambda = λ = λ ",
    ),
    # Handle numeric early termination.
    UnescapeTest.new(
      "numericEnds",
      "&# &#x &#128;43 &copy = &#169f = &#xa9",
      "&# &#x €43 © = ©f = ©",
    ),
    # Handle numeric ISO-8859-1 entity replacements.
    UnescapeTest.new(
      "numericReplacements",
      "Footnote&#x87;",
      "Footnote‡",
    ),
  ]

  it "Test Unescape" do
    UNESCAPE_TESTS.each do |tt|
      puts "Running test - #{tt.html}"
      unescaped = unescape_string(tt.html)
      unescaped.should eq(tt.unescaped)
    end
  end

  it "Test Unescape Escape" do
    ss = [
      "",
      "abc def",
      "a & b",
      "a&amp;b",
      "a &amp b",
      "&quot;",
      "\"",
      "\"<&>\"",
      "&quot;&lt;&amp;&gt;&quot;",
      "3&5==1 && 0<1, \"0&lt;1\", a+acute=&aacute;",
      "The special characters are: <, >, &, ' and \"",
    ]

    ss.each do |s|
      puts "running test - #{s}"
      got = unescape_string(escape_string(s))
      got.should eq(s)
    end
  end
end
