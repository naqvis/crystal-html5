# HTML5 module implements an **HTML5-compliant** `Tokenizer` and `Parser`.
# The relevant specifications include:
# https://html.spec.whatwg.org/multipage/syntax.html and
# https://html.spec.whatwg.org/multipage/syntax.html#tokenization
# Tokenization is done by creating a `Tokenizer` for an `IO`. It is the caller
# responsibility to ensure that provided IO provides UTF-8 encoded HTML.
# The tokenization algorithm implemented by this package is not a line-by-line
# transliteration of the relatively verbose state-machine in the WHATWG
# specification. A more direct approach is used instead, where the program
# counter implies the state, such as whether it is tokenizing a tag or a text
# node. Specification compliance is verified by checking expected and actual
# outputs over a test suite rather than aiming for algorithmic fidelity.
#
# Parsing is done by calling `HTML5.parse` with either a String containing HTML
# or an IO instance. `HTML5.parse` returns a document root as `HTML5::Node` instance.
module HTML5
  VERSION = "0.5.0"

  class HTMLException < Exception
  end

  class MaxBufferExceeded < HTMLException
    def initialize(message = "max buffer exceeded")
      super(message)
    end
  end

  class NoProgressError < HTMLException
    def initialize(message = "multiple read calls returns no data or error")
      super(message)
    end
  end

  # parse returns the parse tree for the HTML from the given *io* into an `HTML5::Node`.
  #
  # It implements the HTML5 parsing algorithm
  # [https://html.spec.whatwg.org/multipage/syntax.html#tree-construction](https://html.spec.whatwg.org/multipage/syntax.html#tree-construction),
  # which is very complicated. The resultant tree can contain implicitly created
  # nodes that have no explicit <tag> listed in passed io's data, and nodes' parents can
  # differ from the nesting implied by a naive processing of start and end
  # <tag>s. Conversely, explicit <tag>s in passed io's data can be silently dropped,
  # with no corresponding node in the resulting tree.
  #
  # The input is assumed to be UTF-8 encoded.
  def self.parse(io : IO, **opts)
    p = Parser.new(io, **opts)
    p.parse
    p.doc
  end

  # parse returns the parse tree for the HTML from the given *html string* into an `HTML5::Node`.
  #
  def self.parse(html : String, **opts)
    parse(IO::Memory.new(html), **opts)
  end

  # parse_fragment parses a fragment of HTML5 and returns the nodes that were
  # found. If the fragment is the InnerHTML for an existing element, pass that
  # element in context.
  #
  # It has the same intricacies as `HTML5.parse`.
  def self.parse_fragment(io : IO, context : Node? = nil, **opts)
    context_tag = ""
    if (cnode = context)
      raise HTMLException.new("parse_fragment of non-element Node") unless cnode.type.element?

      # The next check isn't jsut context.data_atom.to_s == context.data because
      # it is valid to pass an element whose tag isn't a known atom. For example,
      # Atom.zero and data = "tagfromthefuture" is perfectly consistent.
      unless cnode.data_atom == Atom.lookup(cnode.data.to_slice)
        raise HTMLException.new("inconsistent Node: data_atom=#{cnode.data_atom}, data=#{cnode.data}")
      end
      context_tag = cnode.data_atom.to_s
    end
    popts = {frameset: false, fragment: true}.merge(opts)
    p = Parser.new(io, **popts)
    p.context = context
    if context.nil? || context.try &.namespace.empty?
      p.tokenizer = Tokenizer.new(io, context_tag)
    end

    root = Node.new(
      type: NodeType::Element,
      data_atom: Atom::Html,
      data: Atom::Html.to_s
    )
    p.doc.append_child(root)
    p.oe = NodeStack.new([root])
    if (cnode = context) && (cnode.data_atom == Atom::Template)
      p.template_stack << ->ParserHelper.in_template_im(Parser)
    end
    p.reset_insertion_mode
    if (cnode = context)
      while cnode
        if cnode.type.element? && cnode.data_atom == Atom::Form
          p.form = cnode
          break
        end
        cnode = cnode.parent
      end
    end
    p.parse
    parent = p.doc
    parent = root if context
    result = Array(Node).new
    c = parent.first_child
    while c
      ns = c.next_sibling
      parent.remove_child(c)
      result << c
      c = ns
    end
    result
  end

  def self.parse_fragment(html : String, context : Node? = nil, **opts)
    parse_fragment(IO::Memory.new(html), context, **opts)
  end
end

require "./html5/**"
