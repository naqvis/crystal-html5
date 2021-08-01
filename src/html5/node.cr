require "./atom"
require "./token"

module HTML5
  # NodeType is a type of a Node
  enum NodeType : UInt32
    Error    = 0
    Text
    Document
    Element
    Comment
    Doctype
    # Raw nodes are not returned by the parser, but can be part of the Node tree
    # passed to insert raw HTML (without escaping). If so, this shard makes no guarantee
    # that the rendered HTML is secure (from e.g. Cross Site Scripting attacks) or well-formed.
    Raw
    ScopeMarker
  end

  # Section 12.2.4.3 says "The markers are inserted when entering applet,
  # object, marquee, template, td, th, and caption elements, and are used
  # to prevent formatting from "leaking" into applet, object, marquee,
  # template, td, th, and caption elements".
  private ScopeMarker = Node.new(type: NodeType::ScopeMarker)

  # An Attribute is an attribute namespace-key-value triple. Namespace is
  # non-empty for foreign attributes like xlink, Key is alphabetic (and hence
  # does not contain escapable characters like '&', '<' or '>'), and Val is
  # unescaped (it looks like "a<b" rather than "a&lt;b").
  #
  # Namespace is only used by the parser, not the tokenizer.
  class Attribute
    property namespace : String
    property key : String
    property val : String

    def initialize(@namespace = "", @key = "", @val = "")
    end

    def clone
      Attribute.new(namespace, key, val)
    end
  end

  # A Node consists of a NodeType and some data (tag name for element nodes,
  # content for text) and are part of a tree of Nodes. Element nodes may also
  # have a `namespace` and contain an array of Attribute. `data` is unescaped, so
  # that it looks like "a<b" rather than "a&lt;b". For element nodes, `data_atom`
  # is the atom for data, or zero if data is not a known tag name.
  #
  # An empty namespace implies a "http://www.w3.org/1999/xhtml" namespace.
  # Similarly, "math" is short for "http://www.w3.org/1998/Math/MathML", and
  # "svg" is short for "http://www.w3.org/2000/svg".
  class Node
    getter parent : Node?
    getter first_child : Node?
    getter last_child : Node?
    getter prev_sibling : Node?
    getter next_sibling : Node?

    getter type : NodeType
    getter data_atom : Atom::Atom
    getter data : String
    getter namespace : String = ""
    getter attr : Array(Attribute)

    protected setter data
    protected setter namespace
    protected setter parent
    protected setter first_child
    protected setter last_child
    protected setter prev_sibling
    protected setter next_sibling

    def initialize(@type, @data_atom = Atom::Atom.zero, @data = "",
                   @namespace = "", @attr = Array(Attribute).new)
    end

    def attributes
      attr.dup
    end

    def [](attribute_name : String)
      self[attribute_name]? || raise KeyError.new("Missing attribute: #{attribute_name}")
    end

    def []?(attribute_name : String)
      attr.find { |a| a.key == attribute_name }
    end

    # Returns `true` if this node is a Document Node
    def document? : Bool
      type.document?
    end

    # Returns `true` if this node is an Element Node
    def element? : Bool
      type.element?
    end

    # Returns `true` if this node is a Text Node
    def text? : Bool
      type.text?
    end

    # Returns `true` if this node is a Comment Node
    def comment? : Bool
      type.comment?
    end

    # Returns `true` if this node is a Doctype Node
    def doctype? : Bool
      type.doctype?
    end

    # Returns `true` if this node is an Error Node
    def error? : Bool
      type.error?
    end

    # insert_before inserts a new_child as a child of self, immediately before old_child
    # in the sequence of self's children. old child may be nil, in which case new child
    # is appended to the end of self's children.
    #
    # It will raise exception if new child already has a parent or sibling
    def insert_before(new_child : Node, old_child : Node?)
      if new_child.parent || new_child.prev_sibling || new_child.next_sibling
        raise HTMLException.new("insert_before called for an attached child node")
      end

      if !old_child.nil?
        prev, next_ = old_child.prev_sibling, old_child
      else
        prev, next_ = last_child, nil
      end
      if (p = prev)
        p.next_sibling = new_child
      else
        @first_child = new_child
      end
      if (n = next_)
        n.prev_sibling = new_child
      else
        @last_child = new_child
      end
      new_child.parent = self
      new_child.prev_sibling = prev
      new_child.next_sibling = next_
    end

    # append_child adds a node as child of self.
    # It will raise exception if c already has a parent or siblings
    def append_child(c : Node)
      if c.parent || c.prev_sibling || c.next_sibling
        raise HTMLException.new("append_child called for an attached child Node")
      end
      last = last_child
      if last
        last.next_sibling = c
      else
        @first_child = c
      end
      @last_child = c
      c.parent = self
      c.prev_sibling = last
    end

    # remove_child remove a node c that is a child of self. Afterwards, c will have
    # no parent and no siblings.
    #
    # It will raise exception if c's parent is not this node
    def remove_child(c : Node)
      raise HTMLException.new("remove_child called for a non-child node") unless c.parent == self

      @first_child = c.next_sibling if @first_child == c
      c.next_sibling.try &.prev_sibling = c.prev_sibling if c.next_sibling

      @last_child = c.prev_sibling if @last_child == c

      c.prev_sibling.try &.next_sibling = c.next_sibling if c.prev_sibling

      c.parent = nil
      c.prev_sibling = nil
      c.next_sibling = nil
    end

    # clone returns a new node with the same type, data and attributes.
    # The clone has no parent, no siblings and no children
    def clone
      Node.new(type: self.type, data_atom: self.data_atom, data: self.data,
        attr: self.attr.dup)
    end

    # `render` renders the parse tree node to the given `IO` writer.
    #
    # Rendering is done on a 'best effort' basis: calling `parse` on the output of
    # `render` will always result in something similar to the original tree, but it
    # is not necessarily an exact clone unless the original tree was 'well-formed'.
    # 'Well-formed' is not easily specified; the HTML5 specification is
    # complicated.
    #
    # Calling `parse` on arbitrary input typically results in a 'well-formed' parse
    # tree. However, it is possible for Parse to yield a 'badly-formed' parse tree.
    # For example, in a 'well-formed' parse tree, no <a> element is a child of
    # another <a> element: parsing "<a><a>" results in two sibling elements.
    # Similarly, in a 'well-formed' parse tree, no <a> element is a child of a
    # <table> element: parsing "<p><table><a>" results in a <p> with two sibling
    # children; the <a> is reparented to the <table>'s parent. However, calling
    # Parse on "<a><table><a>" does not return an error, but the result has an <a>
    # element with an <a> child, and is therefore not 'well-formed'.
    #
    # Programmatically constructed trees are typically also 'well-formed', but it
    # is possible to construct a tree that looks innocuous but, when rendered and
    # re-parsed, results in a different tree. A simple example is that a solitary
    # text node would become a tree containing <html>, <head> and <body> elements.
    # Another example is that the programmatic equivalent of "a<head>b</head>c"
    # becomes "<html><head><head/><body>abc</body></html>".
    def render(io : IO) : Nil
      # Render non-element nodes; these are the easy cases.
      case self.type
      when .error?
        raise HTMLException.new("cannot render an Error Node")
      when .text?
        HTML5.escape(io, data)
        return
      when .document?
        c = first_child
        while c
          c.render(io)
          c = c.next_sibling
        end
        return
      when .element?
        # No-op
      when .comment?
        io << "<!--"
        io << data
        io << "-->"
        return
      when .doctype?
        io << "<!DOCTYPE " << data
        p, s = "", ""
        attr.each do |a|
          if a.key.compare("public", case_insensitive: true) == 0
            p = a.val
          elsif a.key.compare("system", case_insensitive: true) == 0
            s = a.val
          end
        end
        if !p.empty?
          io << " PUBLIC "
          write_quoted(io, p)
          unless s.empty?
            io << " "
            write_quoted(io, s)
          end
        elsif !s.empty?
          io << " SYSTEM "
          write_quoted(io, s)
        end
        io << ">"
        return
      when .raw?
        io << data
        return
      else
        raise HTMLException.new("unknown node type")
      end

      # Render the <xxx> opening tag.
      io << "<" << data
      attr.each do |a|
        io << " "
        unless namespace.empty?
          io << namespace << ":"
        end
        io << a.key << "=\""
        HTML5.escape(io, a.val)
        io << "\""
      end

      if VOID_ELEMENTS.fetch(data, false)
        raise HTMLException.new("void element #{data} has child nodes") if first_child
        io << "/>"
        return
      end
      io << ">"

      # Add initial newline where there is danger of a newline beging ignored.
      if (c = first_child) && c.type.text? && c.data.starts_with?("\n")
        io << "\n" if {"pre", "listing", "textarea"}.includes?(c.data)
      end

      # Render any child nodes.
      case data
      when "iframe", "noembed", "noframes", "noscript", "plaintext", "script", "style", "xmp"
        c = first_child
        while c
          if c.type.text?
            io << c.data
          else
            c.render(io)
          end
          c = c.next_sibling
        end
        if data.compare("plaintext", case_insensitive: true) == 0
          # Don't render anything esle. <plaintext> must be the
          # last element in the file, with no closing tag.

          # raise HTMLException.new("internal error. <plaintext> abort")
          return
        end
      else
        c = first_child
        while c
          c.render(io)
          c = c.next_sibling
        end
      end

      # Render the </xxx> closing tag.
      io << "</" << data << ">"
    end

    # returns the inner text of current node
    def inner_text : String
      String.build do |io|
        output(io, self)
      end
    end

    # Renders node to HTML. `self_only` will render current node only, but if its false
    # it will return the HTML of current node as well as all of its children
    def to_html(self_only : Bool = true) : String
      String.build do |io|
        if self_only
          render(io)
        else
          c = first_child
          while c
            c.render(io)
            c = c.next_sibling
          end
        end
      end
    end

    private def output(io, n)
      case n.type
      when .text?
        return io << n.data
      when .comment?
        return
      end
      child = n.first_child
      while child
        output(io, child)
        child = child.next_sibling
      end
    end

    private def write_quoted(io, s)
      q = s.includes?('"') ? '\'' : '"'
      io << q << s << q
    end

    # Section 12.1.2, "Elements", gives this list of void elements. Void elements
    # are those that can't have any children
    private VOID_ELEMENTS = {
      "area"   => true,
      "base"   => true,
      "br"     => true,
      "col"    => true,
      "embed"  => true,
      "hr"     => true,
      "img"    => true,
      "input"  => true,
      "keygen" => true,
      "link"   => true,
      "meta"   => true,
      "param"  => true,
      "source" => true,
      "track"  => true,
      "wbr"    => true,
    } of String => Bool
  end

  # :nodoc:
  private class NodeStack
    def initialize(@nodes : Array(Node))
    end

    def pop
      @nodes.pop?
    end

    # top returns the most recently pushed node, or nil
    def top
      @nodes.size > 0 ? @nodes[@nodes.size - 1] : nil
    end

    # index returns the index of the top-most occurence of n in the stack, or -1
    # if n is not present
    def index(n : Node)
      @nodes.each_with_index do |s, i|
        return i if s == n
      end
      -1
    end

    # returns wheter a is within stack
    def contains(a : Atom::Atom)
      @nodes.each do |n|
        return true if n.data_atom == a && n.namespace.empty?
      end
      false
    end

    # insert a node at the given index
    def insert(index : Int32, n : Node) : Nil
      @nodes.insert(index, n)
    end

    # removes a node from the stack. It is a no-op if n is not present
    def remove(node : Node?)
      if (n = node)
        @nodes.reject! { |x| x == n }
      end
    end

    def update(arr : Array(Node))
      @nodes = arr
    end

    forward_missing_to @nodes
  end

  # reparents all of src's child nodes to dst
  def self.reparent_children(dst, src : Node)
    loop do
      child = src.first_child
      break if child.nil?
      src.remove_child(child)
      dst.append_child(child)
    end
  end

  # :nodoc:
  private class InsertionModeStack
    def initialize(@ims : Array(InsertionMode))
    end

    def pop
      @ims.pop?
    end

    def top
      @ims.size > 0 ? @ims[@ims.size - 1] : nil
    end

    forward_missing_to @ims
  end
end
