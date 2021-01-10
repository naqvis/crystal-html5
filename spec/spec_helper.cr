require "spec"
require "../src/html5"

module HTML5
  class TestAttrs
    property text : String
    property want : String
    property context : String
    property scripting : Bool

    def initialize(@text, @want, @context, @scripting)
    end
  end

  # check_tree_consistency check that a node and its descendants are all
  # consistent in their parent/child/sibling relationships
  def check_tree_consistency(n, depth = 0)
    fail "tree looks like it contains a cycle" if depth == 1e4
    check_node_consistency(n)
    c = n.first_child
    while c
      check_tree_consistency(c, depth + 1)
      c = c.next_sibling
    end
  end

  # check_node_consistency checks that a node's parent/child/sibling relationships
  # are consistent
  def check_node_consistency(n)
    return if n.nil?
    nparent = 0
    p = n.parent
    while p
      nparent += 1
      fail "parent list looks like an infinite loop" if nparent == 1e4.to_i
      p = p.parent
    end
    nforward = 0
    c = n.first_child
    while c
      nforward += 1
      fail "forward list of children looks like an infinite loop" if nforward == 1e6.to_i
      fail "inconsistent child/parent relationship" unless c.parent == n
      c = c.next_sibling
    end

    nbackward = 0
    c = n.last_child
    while c
      nbackward += 1
      fail "backward list of children looks like an infinite loop" if nbackward == 1e6.to_i
      fail "inconsistent child/parent relationship" unless c.parent == n
      c = c.prev_sibling
    end
    if (parent = n.parent)
      fail "inconsistent parent relationship" if parent == n
      fail "inconsistent parent/first relationship" if parent == n.first_child
      fail "inconsistent parent/last relationship" if parent == n.last_child
      fail "inconsistent parent/prev relationship" if parent == n.prev_sibling
      fail "inconsistent parent/next relationship" if parent == n.next_sibling

      parent_has_n_as_a_child = false
      c = parent.first_child
      while c
        if c == n
          parent_has_n_as_a_child = true
          break
        end
        c = c.next_sibling
      end

      fail "inconsistent parent/child relationship" unless parent_has_n_as_a_child
    end

    if (ps = n.prev_sibling) && (ps.next_sibling != n)
      fail "inconsistent prev/next relationship"
    end

    if (ns = n.next_sibling) && (ns.prev_sibling != n)
      fail "inconsistent next/prev relationship"
    end

    if n.first_child.nil? != n.last_child.nil?
      fail "inconsistent first/last relationship"
    end

    if !n.first_child.nil? && n.first_child == n.last_child
      # we have a sole child.
      if !n.first_child.try &.prev_sibling.nil? || !n.first_child.try &.next_sibling.nil?
        fail "inconsistent sole child's sibling relationship"
      end
    end

    seen = {} of Node => Bool
    c = n.first_child
    last = c
    while c
      if seen.has_key?(c) && seen[c]
        fail "inconsistent repeated child"
      end
      seen[c] = true
      last = c
      c = c.next_sibling
    end

    fail "inconsistent last relationship" unless last == n.last_child
    c = n.last_child
    first = c
    while c
      fail "inconsistent missing child" unless seen.has_key?(c)
      seen.delete(c)
      first = c
      c = c.prev_sibling
    end

    fail "inconsistent first relationship" unless first == n.first_child
    fail "inconsistent forwards/backwards child list" unless seen.size == 0
  end

  def read_parse_test(r : IO)
    ta = TestAttrs.new("", "", "", true)
    line = r.gets('\n')
    return if line.nil?

    # Read the HTML.
    line.should eq("#data\n")
    str = String.build do |sb|
      line = r.each_line do |s|
        break s if s.size > 0 && s[0] == '#'
        sb << s
        sb << "\n"
      end
    end
    ta.text = str.chomp('\n')

    # Skip the error list
    line.should eq("#errors")
    line = r.each_line do |s|
      break s if s[0] == '#'
    end
    line = line || ""
    if line.starts_with?("#script-")
      case
      when line.ends_with?("-on")
        ta.scripting = true
      when line.ends_with?("-off")
        ta.scripting = false
      else
        fail "got #{line} want \"#script-on\" or \"#script-off\""
      end
      line = r.each_line do |s|
        break s if s[0] == '#'
      end
    end

    if "#document-fragment".compare((line || "").strip) == 0
      line = r.gets('\n', chomp: true) || ""
      ta.context = line.strip
      line = r.gets('\n')
    end

    # Read the dump of what the parse tree should be
    unless "#document".compare((line || "").strip) == 0
      fail "got #{line} want '#document' compare: #{"#document".compare(line || "")}"
    end

    in_quote = false
    str = String.build do |sb|
      r.each_line(chomp: false) do |line|
        trimmed = line.strip("\n |")
        if trimmed.size > 0
          if line[0] == '|' && trimmed[0] == '"'
            in_quote = true
          end
          if trimmed[-1] == '"' && !(line[0] == '|' && trimmed.size == 1)
            in_quote = false
          end
        end
        break if line.size == 0 || line.size == 1 && line[0] == '\n' && !in_quote
        sb << line
      end
    end
    ta.want = str
    ta
  end

  def dump_indent(w, level)
    w << "| "
    w << "  " * level
  end

  def dump_level(w, n, level)
    dump_indent(w, level)
    level += 1
    case n.type
    when .error?
      fail "unexpected Error Node"
    when .document?
      fail "unexpected Document Node"
    when .element?
      if !n.namespace.empty?
        w << "<#{n.namespace} #{n.data}>"
      else
        w << "<#{n.data}>"
      end
      attr = n.attr.sort do |a, b|
        if a.namespace != b.namespace
          a.namespace <=> b.namespace
        else
          a.key <=> b.key
        end
      end
      attr.each do |a|
        w << "\n"
        dump_indent(w, level)
        if a.namespace.empty?
          w << "#{a.key}=\"#{a.val}\""
        else
          w << "#{a.namespace} #{a.key}=\"#{a.val}\""
        end
      end
      if n.namespace.empty? && n.data_atom == Atom::Template
        w << "\n"
        dump_indent(w, level)
        level += 1
        w << "content"
      end
    when .text?
      w << "\"#{n.data}\""
    when .comment?
      w << "<!-- #{n.data} -->"
    when .doctype?
      w << "<!DOCTYPE #{n.data}"
      if n.attr.size > 0
        p, s = "", ""
        n.attr.each do |a|
          if a.key == "public"
            p = a.val
          elsif a.key == "system"
            s = a.val
          end
        end
        if !p.empty? || !s.empty?
          w << " \"#{p}\""
          w << " \"#{s}\""
        end
      end
      w << ">"
    when .scope_marker?
      fail "unexpected ScopeMarker Node"
    else
      fail "unknown code type"
    end
    w << "\n"
    c = n.first_child
    while c
      dump_level(w, c, level)
      c = c.next_sibling
    end
  end

  def dump(n)
    return "" if n.nil? || n.first_child.nil?
    io = IO::Memory.new
    c = n.first_child
    while c
      dump_level(io, c, 0)
      c = c.next_sibling
    end
    io.to_s
  end

  # test_parse_case tests one test case from the test files. IF the test does not
  # pass, it returns an error explain the failure.
  # test is the HTML to be parsed, want is the dump of the correct parse tree,
  # and context is the name of the context node, if any.
  def test_parse_case(text, want, ctx, **opts)
    if ctx.empty?
      doc = parse(text, **opts)
    else
      namespace = ""
      if (i = ctx.index(' ')) && (i >= 0)
        namespace, ctx = ctx[...i], ctx[i + 1..]
      end
      cnode = Node.new(
        type: NodeType::Element,
        data_atom: Atom.lookup(ctx.to_slice),
        data: ctx,
        namespace: namespace,
      )

      nodes = parse_fragment(text, cnode, **opts)
      doc = Node.new(type: NodeType::Document)
      nodes.each do |n|
        doc.append_child(n)
      end
    end

    check_tree_consistency(doc)

    got = dump(doc)

    # Compare the parsed tree to the #document section
    got.should eq(want)

    # return if Render_Test_Blacklist[text]? || !context.empty?
  end
end
