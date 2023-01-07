require "./spec_helper"
require "math"

module HTML5
  record TokenTest, desc : String, html : String, golden : String

  TOKEN_TESTS = [
    TokenTest.new(
      "empty",
      "",
      "",
    ),
    # A single text node. The tokenizer should not break text nodes on whitespace,
    # nor should it normalize whitespace within a text node.
    TokenTest.new(
      "text",
      "foo  bar",
      "foo  bar",
    ),
    # An entity.
    TokenTest.new(
      "entity",
      "one &lt; two",
      "one &lt; two",
    ),
    # A start, self-closing and end tag. The tokenizer does not care if the start
    # and end tokens don't match; that is the job of the parser.
    TokenTest.new(
      "tags",
      "<a/>b<c/>d</e>",
      "<a/>$b$<c/>$d$</e>",
    ),
    # Angle brackets that aren't a tag.
    TokenTest.new(
      "not a tag #0",
      "<",
      "&lt;",
    ),
    TokenTest.new(
      "not a tag #1",
      "</",
      "&lt;/",
    ),
    TokenTest.new(
      "not a tag #2",
      "</>",
      "<!---->",
    ),
    TokenTest.new(
      "not a tag #3",
      "a</>b",
      "a$<!---->$b",
    ),
    TokenTest.new(
      "not a tag #4",
      "</ >",
      "<!-- -->",
    ),
    TokenTest.new(
      "not a tag #5",
      "</.",
      "<!--.-->",
    ),
    TokenTest.new(
      "not a tag #6",
      "</.>",
      "<!--.-->",
    ),
    TokenTest.new(
      "not a tag #7",
      "a < b",
      "a &lt; b",
    ),
    TokenTest.new(
      "not a tag #8",
      "<.>",
      "&lt;.&gt;",
    ),
    TokenTest.new(
      "not a tag #9",
      "a<<<b>>>c",
      "a&lt;&lt;$<b>$&gt;&gt;c",
    ),
    TokenTest.new(
      "not a tag #10",
      "if x<0 and y < 0 then x*y>0",
      "if x&lt;0 and y &lt; 0 then x*y&gt;0",
    ),
    TokenTest.new(
      "not a tag #11",
      "<<p>",
      "&lt;$<p>",
    ),
    # EOF in a tag name.
    TokenTest.new(
      "tag name eof #0",
      "<a",
      "",
    ),
    TokenTest.new(
      "tag name eof #1",
      "<a ",
      "",
    ),
    TokenTest.new(
      "tag name eof #2",
      "a<b",
      "a",
    ),
    TokenTest.new(
      "tag name eof #3",
      "<a><b",
      "<a>",
    ),
    TokenTest.new(
      "tag name eof #4",
      "<a x",
      "",
    ),
    # Some malformed tags that are missing a '>'.
    TokenTest.new(
      "malformed tag #0",
      "<p</p>",
      "<p< p=\"\">",
    ),
    TokenTest.new(
      "malformed tag #1",
      "<p </p>",
      "<p <=\"\" p=\"\">",
    ),
    TokenTest.new(
      "malformed tag #2",
      "<p id",
      "",
    ),
    TokenTest.new(
      "malformed tag #3",
      "<p id=",
      "",
    ),
    TokenTest.new(
      "malformed tag #4",
      "<p id=>",
      "<p id=\"\">",
    ),
    TokenTest.new(
      "malformed tag #5",
      "<p id=0",
      "",
    ),
    TokenTest.new(
      "malformed tag #6",
      "<p id=0</p>",
      "<p id=\"0&lt;/p\">",
    ),
    TokenTest.new(
      "malformed tag #7",
      "<p id=\"0</p>",
      "",
    ),
    TokenTest.new(
      "malformed tag #8",
      "<p id=\"0\"</p>",
      "<p id=\"0\" <=\"\" p=\"\">",
    ),
    TokenTest.new(
      "malformed tag #9",
      "<p></p id",
      "<p>",
    ),
    # Raw text and RCDATA.
    TokenTest.new(
      "basic raw text",
      "<script><a></b></script>",
      "<script>$&lt;a&gt;&lt;/b&gt;$</script>",
    ),
    TokenTest.new(
      "unfinished script end tag",
      "<SCRIPT>a</SCR",
      "<script>$a&lt;/SCR",
    ),
    TokenTest.new(
      "broken script end tag",
      "<SCRIPT>a</SCR ipt>",
      "<script>$a&lt;/SCR ipt&gt;",
    ),
    TokenTest.new(
      "EOF in script end tag",
      "<SCRIPT>a</SCRipt",
      "<script>$a&lt;/SCRipt",
    ),
    TokenTest.new(
      "scriptx end tag",
      "<SCRIPT>a</SCRiptx",
      "<script>$a&lt;/SCRiptx",
    ),
    TokenTest.new(
      "' ' completes script end tag",
      "<SCRIPT>a</SCRipt ",
      "<script>$a",
    ),
    TokenTest.new(
      "'>' completes script end tag",
      "<SCRIPT>a</SCRipt>",
      "<script>$a$</script>",
    ),
    TokenTest.new(
      "self-closing script end tag",
      "<SCRIPT>a</SCRipt/>",
      "<script>$a$</script>",
    ),
    TokenTest.new(
      "nested script tag",
      "<SCRIPT>a</SCRipt<script>",
      "<script>$a&lt;/SCRipt&lt;script&gt;",
    ),
    TokenTest.new(
      "script end tag after unfinished",
      "<SCRIPT>a</SCRipt</script>",
      "<script>$a&lt;/SCRipt$</script>",
    ),
    TokenTest.new(
      "script/style mismatched tags",
      "<script>a</style>",
      "<script>$a&lt;/style&gt;",
    ),
    TokenTest.new(
      "style element with entity",
      "<style>&apos;",
      "<style>$&amp;apos;",
    ),
    TokenTest.new(
      "textarea with tag",
      "<textarea><div></textarea>",
      "<textarea>$&lt;div&gt;$</textarea>",
    ),
    TokenTest.new(
      "title with tag and entity",
      "<title><b>K&amp;R C</b></title>",
      "<title>$&lt;b&gt;K&amp;R C&lt;/b&gt;$</title>",
    ),
    TokenTest.new(
      "title with trailing '&lt;' entity",
      "<title>foobar<</title>",
      "<title>$foobar&lt;$</title>",
    ),
    # DOCTYPE tests.
    TokenTest.new(
      "Proper DOCTYPE",
      "<!DOCTYPE html>",
      "<!DOCTYPE html>",
    ),
    TokenTest.new(
      "DOCTYPE with no space",
      "<!doctypehtml>",
      "<!DOCTYPE html>",
    ),
    TokenTest.new(
      "DOCTYPE with two spaces",
      "<!doctype  html>",
      "<!DOCTYPE html>",
    ),
    TokenTest.new(
      "looks like DOCTYPE but isn't",
      "<!DOCUMENT html>",
      "<!--DOCUMENT html-->",
    ),
    TokenTest.new(
      "DOCTYPE at EOF",
      "<!DOCtype",
      "<!DOCTYPE >",
    ),
    # XML processing instructions.
    TokenTest.new(
      "XML processing instruction",
      "<?xml?>",
      "<!--?xml?-->",
    ),
    # Comments.
    TokenTest.new(
      "comment0",
      "abc<b><!-- skipme --></b>def",
      "abc$<b>$<!-- skipme -->$</b>$def",
    ),
    TokenTest.new(
      "comment1",
      "a<!-->z",
      "a$<!---->$z",
    ),
    TokenTest.new(
      "comment2",
      "a<!--->z",
      "a$<!---->$z",
    ),
    TokenTest.new(
      "comment3",
      "a<!--x>-->z",
      "a$<!--x>-->$z",
    ),
    TokenTest.new(
      "comment4",
      "a<!--x->-->z",
      "a$<!--x->-->$z",
    ),
    TokenTest.new(
      "comment5",
      "a<!>z",
      "a$<!---->$z",
    ),
    TokenTest.new(
      "comment6",
      "a<!->z",
      "a$<!----->$z",
    ),
    TokenTest.new(
      "comment7",
      "a<!---<>z",
      "a$<!---<>z-->",
    ),
    TokenTest.new(
      "comment8",
      "a<!--z",
      "a$<!--z-->",
    ),
    TokenTest.new(
      "comment9",
      "a<!--z-",
      "a$<!--z-->",
    ),
    TokenTest.new(
      "comment10",
      "a<!--z--",
      "a$<!--z-->",
    ),
    TokenTest.new(
      "comment11",
      "a<!--z---",
      "a$<!--z--->",
    ),
    TokenTest.new(
      "comment12",
      "a<!--z----",
      "a$<!--z---->",
    ),
    TokenTest.new(
      "comment13",
      "a<!--x--!>z",
      "a$<!--x-->$z",
    ),
    # An attribute with a backslash.
    TokenTest.new(
      "backslash",
      "<p id=\"a\"b\">",
      "<p id=\"a\" b\"=\"\">",
    ),
    # Entities, tag name and attribute key lower-casing, and whitespace
    # normalization within a tag.
    TokenTest.new(
      "tricky",
      "<p \t\n iD=\"a&quot;B\"  foo=\"bar\"><EM>te&lt;&amp;;xt</em></p>",
      "<p id=\"a&#34;B\" foo=\"bar\">$<em>$te&lt;&amp;;xt$</em>$</p>",
    ),
    # A nonexistent entity. Tokenizing and converting back to a string should
    # escape the "&" to become "&amp;".
    TokenTest.new(
      "noSuchEntity",
      "<a b=\"c&noSuchEntity;d\">&lt;&alsoDoesntExist;&",
      "<a b=\"c&amp;noSuchEntity;d\">$&lt;&amp;alsoDoesntExist;&amp;",
    ),
    TokenTest.new(
      "entity without semicolon",
      "&notit;&notin;<a b=\"q=z&amp=5&notice=hello&not;=world\">",
      "¬it;∉$<a b=\"q=z&amp;amp=5&amp;notice=hello¬=world\">",
    ),
    TokenTest.new(
      "entity with digits",
      "&frac12;",
      "½",
    ),
    # Attribute tests:
    # http://dev.w3.org/html5/pf-summary/Overview.html#attributes
    TokenTest.new(
      "Empty attribute",
      "<input disabled FOO>",
      "<input disabled=\"\" foo=\"\">",
    ),
    TokenTest.new(
      "Empty attribute, whitespace",
      "<input disabled FOO >",
      "<input disabled=\"\" foo=\"\">",
    ),
    TokenTest.new(
      "Unquoted attribute value",
      "<input value=yes FOO=BAR>",
      "<input value=\"yes\" foo=\"BAR\">",
    ),
    TokenTest.new(
      "Unquoted attribute value, spaces",
      "<input value = yes FOO = BAR>",
      "<input value=\"yes\" foo=\"BAR\">",
    ),
    TokenTest.new(
      "Unquoted attribute value, trailing space",
      "<input value=yes FOO=BAR >",
      "<input value=\"yes\" foo=\"BAR\">",
    ),
    TokenTest.new(
      "Single-quoted attribute value",
      "<input value='yes' FOO='BAR'>",
      "<input value=\"yes\" foo=\"BAR\">",
    ),
    TokenTest.new(
      "Single-quoted attribute value, trailing space",
      "<input value='yes' FOO='BAR' >",
      "<input value=\"yes\" foo=\"BAR\">",
    ),
    TokenTest.new(
      "Double-quoted attribute value",
      "<input value=\"I'm an attribute\" FOO=\"BAR\">",
      "<input value=\"I&#39;m an attribute\" foo=\"BAR\">",
    ),
    TokenTest.new(
      "Attribute name characters",
      "<meta http-equiv=\"content-type\">",
      "<meta http-equiv=\"content-type\">",
    ),
    TokenTest.new(
      "Mixed attributes",
      "a<P V=\"0 1\" w='2' X=3 y>z",
      "a$<p v=\"0 1\" w=\"2\" x=\"3\" y=\"\">$z",
    ),
    TokenTest.new(
      "Attributes with a solitary single quote",
      "<p id=can't><p id=won't>",
      "<p id=\"can&#39;t\">$<p id=\"won&#39;t\">",
    ),
  ]

  it "Test Tokenizer" do
    TOKEN_TESTS.each do |tt|
      puts "Testing - #{tt.desc}"
      z = Tokenizer.new(IO::Memory.new(tt.html))
      unless tt.golden.empty?
        tt.golden.split("$").each_with_index do |s, i|
          fail "#{tt.desc} token #{i}: want #{s}, got Error token" if z.next == TokenType::Error
          actual = z.token.to_s
          fail "#{tt.desc} token #{i}: want #{s} got #{actual}" unless s == actual
        end
      end
      z.next
    end
  end

  it "Test Max Buffer" do
    # Exceeding the maximum buffer size generates Exception
    z = Tokenizer.new(IO::Memory.new("<" + "t"*10))
    z.max_buf = 5
    expect_raises(MaxBufferExceeded, "max buffer exceeded") do
      z.next
    end
    want = "<tttt"
    got = String.new(z.raw)
    fail "buffered before overflow: got #{got} want: #{want}" unless got == want
  end

  it "Test Max Buffer Reconstruction" do
    # Exceeding the maximum buffer size at any point while tokenizing permits
    # reconstructing the original input.
    TOKEN_TESTS.each do |test|
      (1..).each do |max_buf|
        puts "Running Max Buffer reconstruction test - #{test.desc}"
        r = IO::Memory.new(test.html)
        z = Tokenizer.new(r)
        z.max_buf = max_buf
        tokenized = IO::Memory.new
        loop do
          tt = z.next
          tokenized.write(z.raw)
          break if tt.error?
        rescue ex
          tokenized.write(z.raw)
          fail "#{test.desc}: unexpected exception: #{ex.message}" if ex.message != "max buffer exceeded"
          break
        end
        # Anything tokenized along with untokenized input or data left in the reader.
        tokenized.write(z.buffered)
        got = tokenized.to_s
        fail "#{test.desc}: reassembled html: got #{got}, want: #{test.html}" unless got == test.html

        # EOF indicates that we completed tokenization and hence found the max max_buf that
        # generates "max buffer exceeded" exception, so continue to the next test.
        break if z.eof?
      end
    end
  end

  it "Accumulating the raw output for each parse event should reconstruct the original input" do
    TOKEN_TESTS.each do |test|
      z = Tokenizer.new(IO::Memory.new(test.html))
      parsed = IO::Memory.new
      loop do
        tt = z.next
        parsed.write(z.raw)
        break if tt.error?
      end
      got = parsed.to_s
      fail "#{test.desc}: reassembled html: got #{got}, want: #{test.html}" unless got == test.html
    end
  end

  it "Test Buf API" do
    s = "0<a>1</a>2<b>3<a>4<a>5</a>6</b>7</a>8<a/>9"
    z = Tokenizer.new(IO::Memory.new(s))
    result = IO::Memory.new
    depth = 0

    loop do
      tt = z.next
      case tt
      when .error?
        break if z.eof?
      when .text?
        txt = z.text
        result.write(txt || Bytes.empty) if depth > 0
      when .start_tag?, .end_tag?
        tn, _ = z.tag_name
        if tn.try &.size == 1 && tn.try &.[0] == 'a'.ord
          if tt.start_tag?
            depth += 1
          else
            depth -= 1
          end
        end
      else
        #
      end
    end
    u = "14567"
    fail "Test Buf API: want #{u} got #{result}" unless result.to_s == u
  end

  it "Test Convert New Lines" do
    tests = {
      "Mac\rDOS\r\nUnix\n"    => "Mac\nDOS\nUnix\n",
      "Unix\nMac\rDOS\r\n"    => "Unix\nMac\nDOS\n",
      "DOS\r\nDOS\r\nDOS\r\n" => "DOS\nDOS\nDOS\n",
      ""                      => "",
      "\n"                    => "\n",
      "\n\r"                  => "\n\n",
      "\r"                    => "\n",
      "\r\n"                  => "\n",
      "\r\n\n"                => "\n\n",
      "\r\n\r"                => "\n\n",
      "\r\n\r\n"              => "\n\n",
      "\r\r"                  => "\n\n",
      "\r\r\n"                => "\n\n",
      "\r\r\n\n"              => "\n\n\n",
      "\r\r\r\n"              => "\n\n\n",
      "\r \n"                 => "\n \n",
      "xyz"                   => "xyz",
    }

    tests.each do |k, v|
      if (got = String.new(convert_new_lines(k.to_slice))) && (got != v)
        fail "input #{k}: got #{got}, want #{v}"
      end
    end
  end
end
