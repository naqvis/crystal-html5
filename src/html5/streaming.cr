require "./token"
require "./parser"

module HTML5
  # `StreamingHandler` is a callback interface for SAX-style streaming HTML parsing.
  #
  # Implement this module and pass it to `HTML5.stream` to receive events as the
  # HTML5 parser constructs the document tree. Events are emitted in document order
  # as the parser processes tokens — you don't have to wait for the full document
  # to be parsed.
  #
  # The parser still builds the full DOM tree internally (required by the HTML5 spec
  # for correct handling of misnested markup), but your handler receives events
  # incrementally as nodes are created.
  #
  # ### Example
  #
  # ```
  # class MyHandler
  #   include HTML5::StreamingHandler
  #
  #   def on_element_open(tag : String, attrs : Array(HTML5::Attribute), namespace : String)
  #     puts "Open: <#{tag}>"
  #   end
  #
  #   def on_element_close(tag : String, namespace : String)
  #     puts "Close: </#{tag}>"
  #   end
  #
  #   def on_text(text : String)
  #     puts "Text: #{text}" unless text.strip.empty?
  #   end
  # end
  #
  # handler = MyHandler.new
  # HTML5.stream(io, handler)
  # ```
  module StreamingHandler
    # Called when an element node is added to the tree.
    # `tag` is the lower-cased tag name, `attrs` are the element's attributes,
    # and `namespace` is empty for HTML elements or "math"/"svg" for foreign content.
    def on_element_open(tag : String, attrs : Array(Attribute), namespace : String)
    end

    # Called when an element is closed (popped from the stack of open elements).
    # Note: void elements like `<br>` and `<img>` will receive both an
    # `on_element_open` and an `on_element_close` call.
    def on_element_close(tag : String, namespace : String)
    end

    # Called when a text node is added to the tree.
    def on_text(text : String)
    end

    # Called when a comment node is added to the tree.
    def on_comment(text : String)
    end

    # Called when a doctype node is added to the tree.
    def on_doctype(data : String)
    end

    # Called when parsing is complete. The final document `Node` is provided
    # for any post-processing that needs the full tree.
    def on_document_end(doc : Node)
    end
  end

  # :nodoc:
  # A NodeStack wrapper that emits close events when elements are popped.
  private class StreamingNodeStack < NodeStack
    @handler : StreamingHandler

    def initialize(nodes : Array(Node), @handler : StreamingHandler)
      super(nodes)
    end

    def pop
      if (node = top) && node.type.element?
        @handler.on_element_close(node.data, node.namespace)
      end
      super
    end
  end

  # :nodoc:
  # A Node wrapper for the document root that emits events when children
  # (comments, doctypes) are appended directly to it.
  private class StreamingDocNode < Node
    @handler : StreamingHandler

    def initialize(@handler : StreamingHandler)
      super(type: NodeType::Document)
    end

    def append_child(c : Node)
      super(c)
      case c.type
      when .comment?
        @handler.on_comment(c.data)
      when .doctype?
        @handler.on_doctype(c.data)
      when .element?
        @handler.on_element_open(c.data, c.attr, c.namespace)
      when .text?
        @handler.on_text(c.data)
      else
        # skip
      end
    end
  end

  # `StreamingParser` wraps the standard HTML5 parser and emits SAX-style events
  # via a `StreamingHandler` as the document tree is constructed.
  #
  # It works by subclassing `Parser` and intercepting the tree-building methods
  # (`add_child`, `add_text`) to emit events while preserving correct HTML5
  # parsing behavior. Element close events are emitted via a custom NodeStack
  # that intercepts pop operations.
  class StreamingParser < Parser
    @handler : StreamingHandler
    # Suppresses text emission from add_child when add_text is handling it
    @suppress_text_event : Bool = false

    def initialize(r : IO, @handler : StreamingHandler, **opts)
      super(r, **opts)
      # Replace the open elements stack with our streaming-aware version
      @oe = StreamingNodeStack.new([] of Node, @handler)
      # Replace the doc node with our streaming-aware version
      @doc = StreamingDocNode.new(@handler)
    end

    # Override add_child to emit events when nodes are added to the tree.
    def add_child(n : Node)
      # Check if this node will be appended to doc (StreamingDocNode handles those)
      appending_to_doc = !should_foster_parent && top() == @doc
      super(n)
      # Don't emit if StreamingDocNode already emitted for this node
      return if appending_to_doc
      case n.type
      when .element?
        @handler.on_element_open(n.data, n.attr, n.namespace)
      when .text?
        @handler.on_text(n.data) unless @suppress_text_event
      when .comment?
        @handler.on_comment(n.data)
      when .doctype?
        @handler.on_doctype(n.data)
      else
        # Skip scope markers, etc.
      end
    end

    # Override add_text to emit text events correctly for all three code paths:
    # 1. Foster parenting (bypasses add_child)
    # 2. Appending to existing text node (bypasses add_child)
    # 3. New text node (goes through add_child)
    def add_text(text : String)
      return if text.empty?

      if should_foster_parent
        # Path 1: foster_parent is called directly, bypasses add_child
        super(text)
        @handler.on_text(text)
        return
      end

      t = top()
      if (n = t.last_child) && n.type.text?
        # Path 2: text appended to existing node, bypasses add_child
        super(text)
        @handler.on_text(text)
        return
      end

      # Path 3: new text node created via add_child — suppress the text
      # event in add_child to avoid double emission
      @suppress_text_event = true
      super(text)
      @suppress_text_event = false
      @handler.on_text(text)
    end

    # Override oe= to emit close events for elements removed by stack slicing.
    # Many insertion modes do `p.oe = p.oe[...i]` to pop multiple elements.
    def oe=(arr : Array(Node))
      # Emit close events for elements being removed (top to target)
      current_size = @oe.size
      new_size = arr.size
      if new_size < current_size
        (current_size - 1).downto(new_size) do |j|
          node = @oe[j]
          @handler.on_element_close(node.data, node.namespace) if node.type.element?
        end
      end
      @oe.update(arr)
    end

    # Run the parse loop.
    def parse
      loop do
        if (n = @oe.top)
          tokenizer.allow_cdata = !n.namespace.empty?
        end

        # Track doc's children count to detect direct appends that bypass add_child
        # (handled by StreamingDocNode now, so no extra tracking needed)

        tokenizer.next
        @token = tokenizer.token
        if token.type.error?
          if (exception = tokenizer.exception?)
            raise exception if !exception.is_a?(IO::EOFError)
          end
        end
        parse_current_token

        break if (token.type.error? && tokenizer.eof?)
      end

      # Emit close events for any elements still on the stack at EOF
      (@oe.size - 1).downto(0) do |i|
        node = @oe[i]
        @handler.on_element_close(node.data, node.namespace) if node.type.element?
      end

      nil
    end
  end

  # Parses HTML from an `IO` and emits SAX-style streaming events to the given handler.
  #
  # The parser builds the full DOM tree internally (required for correct HTML5 parsing),
  # but the handler receives events incrementally as nodes are constructed. This is useful
  # for processing large documents where you want to react to elements as they appear
  # without waiting for the entire document to be parsed.
  #
  # Returns the complete document `Node` tree (same as `HTML5.parse`).
  #
  # ### Example
  #
  # ```
  # class LinkExtractor
  #   include HTML5::StreamingHandler
  #   getter links = [] of String
  #
  #   def on_element_open(tag : String, attrs : Array(HTML5::Attribute), namespace : String)
  #     if tag == "a"
  #       attrs.each do |attr|
  #         links << attr.val if attr.key == "href"
  #       end
  #     end
  #   end
  # end
  #
  # extractor = LinkExtractor.new
  # doc = HTML5.stream(io, extractor)
  # puts extractor.links
  # ```
  def self.stream(io : IO, handler : StreamingHandler, **opts)
    p = StreamingParser.new(io, handler, **opts)
    p.parse
    handler.on_document_end(p.doc)
    p.doc
  end

  # Parses HTML from a `String` and emits SAX-style streaming events to the given handler.
  def self.stream(html : String, handler : StreamingHandler, **opts)
    stream(IO::Memory.new(html), handler, **opts)
  end

  # Iterates over each token in the HTML input without building a parse tree.
  #
  # This is the lightest-weight streaming option — it tokenizes the HTML and yields
  # each `Token` as it's produced. No tree is built, no memory is accumulated beyond
  # the tokenizer's internal buffer. Runs in constant memory regardless of input size.
  #
  # Tokens are yielded in document order: start tags, text, end tags, comments, doctypes.
  # Note that without tree construction, the token stream reflects the raw markup — it
  # does not include the implicit tags or tree corrections that the full parser would apply.
  #
  # ### Example
  #
  # ```
  # # Extract all text content
  # HTML5.each_token(io) do |token|
  #   print token.data if token.type.text?
  # end
  # ```
  #
  # ```
  # # Find all image sources
  # HTML5.each_token(html_string) do |token|
  #   if token.type.start_tag? && token.data == "img"
  #     token.attr.each do |a|
  #       puts a.val if a.key == "src"
  #     end
  #   end
  # end
  # ```
  def self.each_token(io : IO, &block : Token ->) : Nil
    tokenizer = Tokenizer.new(io)
    loop do
      tokenizer.next
      token = tokenizer.token
      break if token.type.error?
      yield token
    end
    if (ex = tokenizer.exception?) && !ex.is_a?(IO::EOFError)
      raise ex
    end
  end

  # Iterates over each token in the HTML string without building a parse tree.
  def self.each_token(html : String, &block : Token ->) : Nil
    each_token(IO::Memory.new(html), &block)
  end

  # Returns an `Iterator` over the tokens in the HTML input.
  #
  # ### Example
  #
  # ```
  # HTML5.token_iterator(io).each do |token|
  #   puts token.data if token.type.start_tag?
  # end
  # ```
  def self.token_iterator(io : IO) : Iterator(Token)
    TokenIterator.new(io)
  end

  # Returns an `Iterator` over the tokens in the HTML string.
  def self.token_iterator(html : String) : Iterator(Token)
    token_iterator(IO::Memory.new(html))
  end

  # :nodoc:
  private class TokenIterator
    include Iterator(Token)

    def initialize(io : IO)
      @tokenizer = Tokenizer.new(io)
      @done = false
    end

    def next : Token | Stop
      return stop if @done

      @tokenizer.next
      token = @tokenizer.token

      if token.type.error?
        @done = true
        if (ex = @tokenizer.exception?) && !ex.is_a?(IO::EOFError)
          raise ex
        end
        return stop
      end

      token
    end
  end
end
