require "./spec_helper"

module HTML5::Atom
  describe HTML5::Atom do
    it "Test Known Atoms" do
      TEST_ATOM_LIST.each do |want|
        got = lookup(want.to_slice)
        fail "lookup(#{want}) = #{got} (#{got.to_s})" unless got.to_s == want
      end
    end

    it "Test Hits" do
      TABLE.each do |want|
        next if want == Atom.zero
        got = lookup(want.to_s.to_slice)
        fail "lookup(#{want}) = #{got} (#{got})" unless got == want
      end
    end

    it "Test Misses" do
      tests = [
        "",
        "\x00",
        "\xff",
        "A",
        "DIV",
        "Div",
        "dIV",
        "aa",
        "a\x00",
        "ab",
        "abb",
        "abbr0",
        "abbr ",
        " abbr",
        " a",
        "acceptcharset",
        "acceptCharset",
        "accept_charset",
        "h0",
        "h1h2",
        "h7",
        "onClick",
        "λ",
        # The following string has the same hash (0xa1d7fab7) as "onmouseover".
        "\x00\x00\x00\x00\x00\x50\x18\xae\x38\xd0\xb7",
      ]

      tests.each do |tc|
        got = lookup(tc.to_slice)
        fail "lookup(\"#{tc}\"): got \"#{got}\", want 0" unless got == Atom.zero
      end
    end

    it "Test ForeignObject" do
      got = lookup("foreignobject".to_slice)
      fail "lookup(\"foreignobject\"): got \"#{got}\", want \"#{Foreignobject}\"" unless got == Foreignobject

      got = lookup("foreignObject".to_slice)
      fail "lookup(\"foreignObject\"): got \"#{got}\", want \"#{ForeignObject}\"" unless got == ForeignObject

      Foreignobject.to_s.should eq("foreignobject")
      ForeignObject.to_s.should eq("foreignObject")
    end
  end
end
