require "./spec_helper"

# Test handler that records all events for verification
class RecordingHandler
  include HTML5::StreamingHandler

  record ElementOpen, tag : String, attrs : Array(HTML5::Attribute), namespace : String
  record ElementClose, tag : String, namespace : String
  record TextEvent, text : String
  record CommentEvent, text : String
  record DoctypeEvent, data : String
  record DocumentEnd

  alias Event = ElementOpen | ElementClose | TextEvent | CommentEvent | DoctypeEvent | DocumentEnd

  getter events = [] of Event
  getter doc : HTML5::Node? = nil

  def on_element_open(tag : String, attrs : Array(HTML5::Attribute), namespace : String)
    @events << ElementOpen.new(tag, attrs, namespace)
  end

  def on_element_close(tag : String, namespace : String)
    @events << ElementClose.new(tag, namespace)
  end

  def on_text(text : String)
    @events << TextEvent.new(text)
  end

  def on_comment(text : String)
    @events << CommentEvent.new(text)
  end

  def on_doctype(data : String)
    @events << DoctypeEvent.new(data)
  end

  def on_document_end(doc : HTML5::Node)
    @events << DocumentEnd.new
    @doc = doc
  end
end

module HTML5
  describe "HTML5 Streaming" do
    describe "each_token" do
      it "tokenizes a simple document" do
        html = "<p>Hello</p>"
        tokens = [] of HTML5::Token
        HTML5.each_token(html) { |t| tokens << t }

        tokens.size.should eq(3)
        tokens[0].type.start_tag?.should be_true
        tokens[0].data.should eq("p")
        tokens[1].type.text?.should be_true
        tokens[1].data.should eq("Hello")
        tokens[2].type.end_tag?.should be_true
        tokens[2].data.should eq("p")
      end

      it "handles attributes" do
        html = %(<a href="/link" class="btn">Click</a>)
        tokens = [] of HTML5::Token
        HTML5.each_token(html) { |t| tokens << t }

        tokens[0].type.start_tag?.should be_true
        tokens[0].data.should eq("a")
        tokens[0].attr.size.should eq(2)
        tokens[0].attr[0].key.should eq("href")
        tokens[0].attr[0].val.should eq("/link")
        tokens[0].attr[1].key.should eq("class")
        tokens[0].attr[1].val.should eq("btn")
      end

      it "handles self-closing tags" do
        html = "<br/><img src='test.png'/>"
        tokens = [] of HTML5::Token
        HTML5.each_token(html) { |t| tokens << t }

        tokens[0].type.self_closing_tag?.should be_true
        tokens[0].data.should eq("br")
        tokens[1].type.self_closing_tag?.should be_true
        tokens[1].data.should eq("img")
      end

      it "handles comments" do
        html = "<!-- a comment --><p>text</p>"
        tokens = [] of HTML5::Token
        HTML5.each_token(html) { |t| tokens << t }

        tokens[0].type.comment?.should be_true
        tokens[0].data.should eq(" a comment ")
      end

      it "handles doctype" do
        html = "<!DOCTYPE html><html><body></body></html>"
        tokens = [] of HTML5::Token
        HTML5.each_token(html) { |t| tokens << t }

        tokens[0].type.doctype?.should be_true
        tokens[0].data.should eq("html")
      end

      it "works with IO" do
        io = IO::Memory.new("<div>content</div>")
        tokens = [] of HTML5::Token
        HTML5.each_token(io) { |t| tokens << t }

        tokens.size.should eq(3)
        tokens[0].data.should eq("div")
      end

      it "handles empty input" do
        tokens = [] of HTML5::Token
        HTML5.each_token("") { |t| tokens << t }
        tokens.size.should eq(0)
      end

      it "handles nested elements" do
        html = "<div><p><span>text</span></p></div>"
        tokens = [] of HTML5::Token
        HTML5.each_token(html) { |t| tokens << t }

        tokens.map(&.data).should eq(["div", "p", "span", "text", "span", "p", "div"])
      end
    end

    describe "token_iterator" do
      it "iterates over tokens" do
        tags = [] of String
        HTML5.token_iterator("<p>Hello</p><div>World</div>").each do |token|
          tags << token.data if token.type.start_tag?
        end
        tags.should eq(["p", "div"])
      end

      it "works with IO" do
        tags = [] of String
        io = IO::Memory.new("<br/><hr/>")
        HTML5.token_iterator(io).each do |token|
          tags << token.data if token.type.self_closing_tag?
        end
        tags.should eq(["br", "hr"])
      end

      it "handles empty input" do
        count = 0
        HTML5.token_iterator("").each { |_| count += 1 }
        count.should eq(0)
      end
    end

    describe "stream (SAX-style)" do
      it "emits open and close events for a simple document" do
        handler = RecordingHandler.new
        HTML5.stream("<p>Hello</p>", handler)

        opens = handler.events.select(RecordingHandler::ElementOpen)
        opens.map(&.tag).should contain("html")
        opens.map(&.tag).should contain("head")
        opens.map(&.tag).should contain("body")
        opens.map(&.tag).should contain("p")

        closes = handler.events.select(RecordingHandler::ElementClose)
        closes.map(&.tag).should contain("p")
        closes.map(&.tag).should contain("body")
        closes.map(&.tag).should contain("html")
      end

      it "emits text events" do
        handler = RecordingHandler.new
        HTML5.stream("<p>Hello World</p>", handler)

        texts = handler.events.select(RecordingHandler::TextEvent)
        texts.map(&.text).should contain("Hello World")
      end

      it "emits comment events" do
        handler = RecordingHandler.new
        HTML5.stream("<!-- test comment --><p>text</p>", handler)

        comments = handler.events.select(RecordingHandler::CommentEvent)
        comments.size.should be >= 1
        comments.map(&.text).should contain(" test comment ")
      end

      it "emits doctype events" do
        handler = RecordingHandler.new
        HTML5.stream("<!DOCTYPE html><html><body></body></html>", handler)

        doctypes = handler.events.select(RecordingHandler::DoctypeEvent)
        doctypes.size.should eq(1)
        doctypes[0].data.should eq("html")
      end

      it "emits document_end with the complete tree" do
        handler = RecordingHandler.new
        doc = HTML5.stream("<p>test</p>", handler)

        handler.events.last.should be_a(RecordingHandler::DocumentEnd)
        handler.doc.should_not be_nil
        handler.doc.should eq(doc)
      end

      it "returns the same tree as HTML5.parse" do
        html = "<div><p>Hello</p><span>World</span></div>"
        handler = RecordingHandler.new
        stream_doc = HTML5.stream(html, handler)
        parse_doc = HTML5.parse(html)

        dump(stream_doc).should eq(dump(parse_doc))
      end

      it "handles attributes in open events" do
        handler = RecordingHandler.new
        HTML5.stream(%(<a href="/test" id="link1">click</a>), handler)

        a_opens = handler.events.select(RecordingHandler::ElementOpen).select { |e| e.tag == "a" }
        a_opens.size.should eq(1)
        a_opens[0].attrs.size.should eq(2)
        a_opens[0].attrs.find { |a| a.key == "href" }.try(&.val).should eq("/test")
        a_opens[0].attrs.find { |a| a.key == "id" }.try(&.val).should eq("link1")
      end

      it "handles void elements" do
        handler = RecordingHandler.new
        HTML5.stream("<p>before<br>after</p>", handler)

        opens = handler.events.select(RecordingHandler::ElementOpen)
        opens.map(&.tag).should contain("br")

        # br should also get a close event
        closes = handler.events.select(RecordingHandler::ElementClose)
        closes.map(&.tag).should contain("br")
      end

      it "handles implicit tag closure" do
        handler = RecordingHandler.new
        # Two <p> tags — the first is implicitly closed by the second
        HTML5.stream("<p>first<p>second", handler)

        p_closes = handler.events.select(RecordingHandler::ElementClose).select { |e| e.tag == "p" }
        p_closes.size.should eq(2)
      end

      it "handles nested structures" do
        handler = RecordingHandler.new
        HTML5.stream("<table><tr><td>cell</td></tr></table>", handler)

        opens = handler.events.select(RecordingHandler::ElementOpen).map(&.tag)
        opens.should contain("table")
        opens.should contain("tbody") # implicitly created
        opens.should contain("tr")
        opens.should contain("td")
      end

      it "works with IO input" do
        handler = RecordingHandler.new
        io = IO::Memory.new("<p>test</p>")
        HTML5.stream(io, handler)

        handler.events.select(RecordingHandler::TextEvent).map(&.text).should contain("test")
      end

      it "handles a realistic document" do
        html = <<-HTML
        <!DOCTYPE html>
        <html>
        <head><title>Test Page</title></head>
        <body>
          <h1>Welcome</h1>
          <p>This is a <strong>test</strong> page.</p>
          <ul>
            <li>Item 1</li>
            <li>Item 2</li>
          </ul>
          <!-- footer comment -->
        </body>
        </html>
        HTML

        handler = RecordingHandler.new
        doc = HTML5.stream(html, handler)

        # Verify tree is valid
        check_tree_consistency(doc)

        # Verify key events were emitted
        opens = handler.events.select(RecordingHandler::ElementOpen).map(&.tag)
        opens.should contain("html")
        opens.should contain("head")
        opens.should contain("title")
        opens.should contain("body")
        opens.should contain("h1")
        opens.should contain("p")
        opens.should contain("strong")
        opens.should contain("ul")
        opens.should contain("li")

        texts = handler.events.select(RecordingHandler::TextEvent).map(&.text)
        texts.should contain("Test Page")
        texts.should contain("Welcome")

        comments = handler.events.select(RecordingHandler::CommentEvent)
        comments.map(&.text).should contain(" footer comment ")

        doctypes = handler.events.select(RecordingHandler::DoctypeEvent)
        doctypes.size.should eq(1)

        # Document end should be last
        handler.events.last.should be_a(RecordingHandler::DocumentEnd)
      end

      it "produces the same tree as regular parse for complex HTML" do
        html = <<-HTML
        <!DOCTYPE html>
        <html>
        <head><title>Complex</title><meta charset="utf-8"></head>
        <body>
          <div id="main">
            <h1>Title</h1>
            <p>Paragraph with <em>emphasis</em> and <strong>bold</strong>.</p>
            <table>
              <tr><th>Header</th></tr>
              <tr><td>Data</td></tr>
            </table>
            <form action="/submit">
              <input type="text" name="q">
              <button>Submit</button>
            </form>
          </div>
        </body>
        </html>
        HTML

        handler = RecordingHandler.new
        stream_doc = HTML5.stream(html, handler)
        parse_doc = HTML5.parse(html)

        dump(stream_doc).should eq(dump(parse_doc))
      end
    end
  end
end
