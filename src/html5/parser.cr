require "./atom"
require "./node"
require "./insertion_mode"

module HTML5
  # Stop tags for use in pop_until. These come from section 12.2.4.2.
  private DEFAULT_SCOPE_STOP_TAGS = {
    ""     => [Atom::Applet, Atom::Caption, Atom::Html, Atom::Table, Atom::Td, Atom::Th, Atom::Marquee, Atom::Object, Atom::Template],
    "math" => [Atom::AnnotationXml, Atom::Mi, Atom::Mn, Atom::Mo, Atom::Ms, Atom::Mtext],
    "svg"  => [Atom::Desc, Atom::ForeignObject, Atom::Title],
  }

  enum Scope
    Default
    ListItem
    Button
    Table
    TableRow
    TableBody
    Select
  end

  # A parser implements the HTML5 parsing algorithm:
  # https://html.spec.whatwg.org/multipage/syntax.html#tree-construction
  class Parser
    # tokenizer provides the tokens for the parser
    protected property tokenizer : Tokenizer
    # token is the most recently used Token
    protected getter token : Token
    # Self-closing tags like <hr/> are treated as start tags, except that
    # has_self_closing_token is set while they are being processed
    property has_self_closing_token : Bool = false
    # doc is the document root element
    getter doc : Node
    # The stack of open elements (section 12.2.4.2) and active formatting
    # elements (section 12.2.4.3)
    protected property oe : NodeStack
    protected property afe : NodeStack
    # Element pointers (section 12.2.4.4)
    protected property head : Node?
    protected property form : Node?
    # Other parsing state flags (section 12.2.4.5)
    protected property scripting : Bool = false
    protected property frameset_ok : Bool = false
    # The stack of template insertion modes
    protected property template_stack : InsertionModeStack
    # im is the current insertion mode
    protected property im : InsertionMode
    # original_im is the insertion mode to go back to after completing a text
    # or in_table_text insertion mode.
    protected property original_im : InsertionMode?
    # foster_parenting is whether new elements should be inserted according to
    # the foster parenting rules (section 12.2.6.1)
    protected property foster_parenting : Bool = false
    # quirks is whether the parser is operating in "quirks mode."
    protected property quirks : Bool = false
    # fragment is whether the parser is parsing an HTML fragment.
    getter fragment : Bool = false
    # context is the context element when parsing an HTML fragment
    # (section 12.4)
    protected property context : Node?

    def initialize(r : IO, **opts)
      @tokenizer = Tokenizer.new(r)
      @doc = Node.new(type: NodeType::Document)
      @scripting = opts.fetch(:scripting, true)
      @frameset_ok = opts.fetch(:frameset, true)
      @fragment = opts.fetch(:fragment, false)

      @im = ->ParserHelper.initial_im(Parser)
      @token = Token.new
      @oe = NodeStack.new([] of Node)
      @afe = NodeStack.new([] of Node)
      @template_stack = InsertionModeStack.new([] of InsertionMode)
    end

    def oe=(arr : Array(Node))
      oe.update(arr)
    end

    def top : Node
      if (n = @oe.top)
        return n
      end
      @doc
    end

    # pop_until pops the stack of open elements at the highest element whose tag
    # is in matchTags, provided there is no higher element in the scope's stop
    # tags (as defined in section 12.2.4.2). It returns whether or not there was
    # such an element. If there was not, popUntil leaves the stack unchanged.
    #
    # For example, the set of stop tags for table scope is: "html", "table". If
    # the stack was:
    # ["html", "body", "font", "table", "b", "i", "u"]
    # then pop_until(tableScope, "font") would return false, but
    # pop_until(tableScope, "i") would return true and the stack would become:
    # ["html", "body", "font", "table", "b"]
    #
    # If an element's tag is in both the stop tags and match_tags, then the stack
    # will be popped and the function returns true (provided, of course, there was
    # no higher element in the stack that was also in the stop tags). For example,
    # pop_until(tableScope, "table") returns true and leaves:
    # ["html", "body", "font"]
    def pop_until(s : Scope, *match_tags : Atom::Atom)
      if (i = index_of_element_in_scope(s, *match_tags)) && (i != -1)
        self.oe = self.oe[...i]
        return true
      end
      false
    end

    # index_of_element_in_scope returns the index of in @oe of the highest element whose
    # tag is in match_tags that is in scope. If no matching element is in scope, it returns -1
    def index_of_element_in_scope(s, *match_tags)
      (@oe.size - 1).downto(0) do |i|
        tag_atom = @oe[i].data_atom
        if @oe[i].namespace.empty?
          match_tags.each do |t|
            return i if t == tag_atom
          end
          case s
          when .default?
            # No-op
          when .list_item?
            return -1 if {Atom::Ol, Atom::Ul}.includes?(tag_atom)
          when .button?
            return -1 if tag_atom == Atom::Button
          when .table?
            return -1 if {Atom::Html, Atom::Table, Atom::Template}.includes?(tag_atom)
          when .select?
            return -1 unless {Atom::Optgroup, Atom::Option}.includes?(tag_atom)
          else
            raise HTMLException.new("unreachable")
          end
        end

        if s.default? || s.list_item? || s.button?
          DEFAULT_SCOPE_STOP_TAGS[oe[i].namespace]?.try &.each do |t|
            return -1 if t == tag_atom
          end
        end
      end
      -1
    end

    # element_in_scope is like pop_until, except that it doesn't modify the stack of
    # open elements
    def element_in_scope(s : Scope, *match_tags)
      index_of_element_in_scope(s, *match_tags) != -1
    end

    # clear_stack_to_context pops elements off the stack of open elements until a
    # scope-defined element is found.
    def clear_stack_to_context(s : Scope)
      (@oe.size - 1).downto(0) do |i|
        tag_atom = @oe[i].data_atom
        case s
        when .table?
          if {Atom::Html, Atom::Table, Atom::Template}.includes?(tag_atom)
            self.oe = @oe[...i + 1]
            break
          end
        when .table_row?
          if {Atom::Html, Atom::Tr, Atom::Template}.includes?(tag_atom)
            self.oe = @oe[...i + 1]
            break
          end
        when .table_body?
          if {Atom::Html, Atom::Tbody, Atom::Tfoot, Atom::Thead, Atom::Template}.includes?(tag_atom)
            self.oe = @oe[...i + 1]
            break
          end
        else
          raise HTMLException.new("unreachable")
        end
      end
    end

    # parse_generic_raw_text_elements implements the generic raw text element parsing
    # algorithm defined in 12.2.6.2.
    # https://html.spec.whatwg.org/multipage/parsing.html#parsing-elements-that-contain-only-text
    # TODO: Since both RAWTEXT and RCDATA states are treated as tokenizer's part
    # officially, need to make tokenizer consider both states.
    def parse_generic_raw_text_elements
      add_element
      @original_im = @im
      @im = ->ParserHelper.text_im(Parser)
    end

    # generate_implied_end_tags pops nodes off the stack of open elements as long as
    # the top node has a tag name of dd, dt, li, optgroup, option, p, rb, rp, rt or rtc.
    # If exceptions are specified, nodes with that name will not be popped off.
    def generate_implied_end_tags(*exceptions)
      i = 0
      (@oe.size - 1).downto(0) do |i0|
        i = i0
        n = @oe[i0]
        break unless n.type.element?
        if {Atom::Dd, Atom::Dt, Atom::Li, Atom::Optgroup, Atom::Option, Atom::P, Atom::Rb,
            Atom::Rp, Atom::Rt, Atom::Rtc}.includes?(n.data_atom)
          exceptions.each do |except|
            if n.data == except
              self.oe = @oe[...i0 + 1]
              return
            end
          end
          next
        end
        break
      end
      self.oe = @oe[...i + 1]
    end

    # add_child adds a child node n to the top element, and pushes n onto the stack
    # of open elements if it is an element node.
    def add_child(n : Node)
      should_foster_parent ? foster_parent(n) : top().append_child(n)
      (@oe << n) if n.type.element?
    end

    # should_foster_parent returns whether the next node to be added should be
    # foster parented.
    def should_foster_parent
      return {Atom::Table, Atom::Tbody, Atom::Tfoot,
              Atom::Thead, Atom::Tr}.includes?(top().data_atom) if @foster_parenting
      false
    end

    # foster_parent adds a child node according to the foster parenting rules.
    # Section 12.2.6.1, "foster parenting"
    def foster_parent(n : Node)
      i, j = 0, 0
      table : Node? = nil
      parent : Node? = nil
      prev : Node? = nil
      template : Node? = nil

      (@oe.size - 1).downto(0) do |i1|
        i = i1
        if @oe[i1].data_atom == Atom::Table
          table = @oe[i1]
          break
        end
      end

      (@oe.size - 1).downto(0) do |j1|
        j = j1
        if @oe[j1].data_atom == Atom::Template
          template = @oe[j1]
          break
        end
      end

      if (t = template) && (table.nil? || j > i)
        t.append_child(n)
        return
      end

      # The foster parent is the html element.
      parent = table.nil? ? oe[0] : table.parent

      parent = @oe[i - 1] if parent.nil?

      if (t = table)
        prev = t.prev_sibling
      else
        prev = parent.last_child
      end

      if (p = prev) && p.type.text? && n.type.text?
        p.data += n.data
        return
      end

      parent.insert_before(n, table)
    end

    # add_text adds text to the preceding node if it is a Text Node, or else it
    # calls add_child with a new Text Node
    def add_text(text : String)
      return if text.empty?

      if should_foster_parent
        foster_parent(Node.new(type: NodeType::Text, data: text))
        return
      end

      t = top()
      if (n = t.last_child) && n.type.text?
        n.data += text
        return
      end

      add_child(Node.new(
        type: NodeType::Text,
        data: text
      ))
    end

    # add_element adds a child element based on the current token.
    def add_element
      add_child(Node.new(
        type: NodeType::Element,
        data_atom: @token.data_atom,
        data: @token.data,
        attr: @token.attr.clone
      ))
    end

    # Section 12.2.4.3
    def add_formatting_element
      tag_atom, attr = @token.data_atom, @token.attr.clone
      add_element

      # Implement the Noah's Ark clause, but with three per family instead of two.
      identical_elements = 0
      (@afe.size - 1).downto(0) do |i|
        n = @afe[i]
        break if n.type.scope_marker?
        next unless n.type.element?
        next unless n.namespace.empty?
        next unless n.data_atom == tag_atom
        next unless n.attr.size == attr.size

        continue = n.attr.each do |t0|
          found = attr.each do |t1|
            if t0.key == t1.key && t0.namespace == t1.namespace && t0.val == t1.val
              # Found a match for this attribute, continue with the next attribute
              break true
            end
          end
          next if found

          # If we get here, there is no attribute that matches a.
          # Therefore the element is not identical to the new one.
          break true
        end
        next if continue

        identical_elements += 1
        @afe.remove(n) if identical_elements >= 3
      end
      @afe << top()
    end

    # Section 12.2.4.3.
    def clear_active_formatting_elements
      loop do
        return if (n = @afe.pop) && (@afe.size == 0 || n.type.scope_marker?)
      end
    end

    # Section 12.2.4.3.
    def reconstruct_active_formatting_elements
      if (n = @afe.top)
        return if n.type.scope_marker? || @oe.index(n) != -1
        i = @afe.size - 1
        while !n.type.scope_marker? && @oe.index(n) == -1
          if i == 0
            i = -1
            break
          end
          i -= 1
          n = @afe[i]
        end
        loop do
          i += 1
          clone = @afe[i].clone
          add_child(clone)
          @afe[i] = clone
          break if i == @afe.size - 1
        end
      end
    end

    # Section 12.2.5
    def acknowledge_self_closing_tag
      @has_self_closing_token = false
    end

    # set_original_im sets the insertion mode to return to after completing a text or
    # inTableText insertion mode.
    # Section 12.2.4.1, "using the rules for".
    def set_original_im
      raise HTMLException.new("bad parser state: original_im was set twice") unless @original_im.nil?
      @original_im = @im
    end

    # Section 12.2.4.1, "reset the insertion mode".
    def reset_insertion_mode
      (@oe.size - 1).downto(0) do |i|
        n = @oe[i]
        last = i == 0
        if (last) && (node = @context)
          n = node
        end
        case n.data_atom
        when Atom::Select
          unless last
            ancestor = n
            first = @oe[0]
            while (ancestor && first) && (ancestor != first)
              ancestor = @oe[@oe.index(ancestor) - 1]
              if ancestor.data_atom == Atom::Template
                @im = ->ParserHelper.in_select_im(Parser)
                return
              elsif ancestor.data_atom == Atom::Table
                @im = ->ParserHelper.in_select_in_table_im(Parser)
                return
              end
            end
          end
          @im = ->ParserHelper.in_select_im(Parser)
        when Atom::Td, Atom::Th
          # TODO: remove this divergence from the HTML5 spec
          @im = ->ParserHelper.in_cell_im(Parser)
        when Atom::Tr
          @im = ->ParserHelper.in_row_im(Parser)
        when Atom::Tbody, Atom::Thead, Atom::Tfoot
          @im = ->ParserHelper.in_table_body_im(Parser)
        when Atom::Caption
          @im = ->ParserHelper.in_caption_im(Parser)
        when Atom::Colgroup
          @im = ->ParserHelper.in_column_group_im(Parser)
        when Atom::Table
          @im = ->ParserHelper.in_table_im(Parser)
        when Atom::Template
          # TODO: remove this divergence from the HTML5 spec
          next unless n.namespace.empty?
          if (tim = @template_stack.top)
            @im = tim
          end
        when Atom::Head
          # TODO: remove this divergence from HTML5 spec
          @im = ->ParserHelper.in_head_im(Parser)
        when Atom::Body
          @im = ->ParserHelper.in_body_im(Parser)
        when Atom::Frameset
          @im = ->ParserHelper.in_frameset_im(Parser)
        when Atom::Html
          @im = @head.nil? ? ->ParserHelper.before_head_im(Parser) : ->ParserHelper.after_head_im(Parser)
        else
          if last
            @im = ->ParserHelper.in_body_im(Parser)
            return
          end
          next
        end
        return
      end
    end

    # Section 12.2.4.2
    def adjusted_current_node
      return @context if oe.size == 1 && fragment && !context.nil?
      oe.top
    end

    # Section 12.2.6
    def in_foreign_content
      return false if oe.size == 0
      n = adjusted_current_node || return false
      return false if n.namespace.empty?

      if ParserHelper.mathml_text_integration_point(n)
        return false if token.type.start_tag? && !{Atom::Mglyph, Atom::Malignmark}.includes?(token.data_atom)
        return false if token.type.text?
      end
      return false if n.namespace == "math" && n.data_atom == Atom::AnnotationXml && token.type.start_tag? && token.data_atom == Atom::Svg
      return false if ParserHelper.html_integration_point(n) && (token.type.start_tag? || token.type.text?)
      return false if token.type.error?
      true
    end

    # parses a token as thoug it had appeared in the parser's input
    def parse_implied_token(t : TokenType, atom : Atom::Atom, data : String)
      real_token, self_closing = self.token, self.has_self_closing_token
      @token = Token.new(
        type: t,
        data_atom: atom,
        data: data
      )
      self.has_self_closing_token = false
      parse_current_token
      @token, @has_self_closing_token = real_token, self_closing
    end

    # runs the current token through the parsing routines until it is consumed.
    def parse_current_token
      if token.type.self_closing_tag?
        @has_self_closing_token = true
        @token.type = TokenType::StartTag
      end

      consumed = false
      while !consumed
        consumed = in_foreign_content() ? ParserHelper.parse_foreign_content(self) : @im.call(self)
      end

      # This is a parser error, but ignore it
      @has_self_closing_token &&= false
    end

    def parse
      # Iterate until EOF. Any other error will cause early return
      loop do
        # CDATA sections are allowed only in foreign content.
        if (n = @oe.top)
          tokenizer.allow_cdata = !n.namespace.empty?
        end
        # read adn parse the next token.
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
      nil
    end

    # This is the "adoption agency" algorithm, described at
    # https://html.spec.whatwg.org/multipage/syntax.html#adoptionAgency

    # TODO: this is a fairly literal line-by-line translation of that algorithm.
    # Once the code successfully parses the comprehensive test suite, we should
    # refactor this code to be more idiomatic.
    def in_body_end_tag_formatting(atom : Atom::Atom, tag_name : String)
      # Steps 1-2
      if (current = oe.top) && (current.data == tag_name) && (afe.index(current) == -1)
        oe.pop
        return
      end
      # Steps 3-5. The out loop
      8.times do
        # Step 6. Find the formatting element.
        formatting_element : Node? = nil
        (afe.size - 1).downto(0) do |j|
          break if afe[j].type.scope_marker?
          if afe[j].data_atom == atom
            formatting_element = afe[j]
            break
          end
        end

        if formatting_element.nil?
          in_body_end_tag_other(atom, tag_name)
          return
        end

        # Step 7. Ignore the tag if formatting element is not in the stack of open elements.
        fe_index = oe.index(formatting_element)
        if fe_index == -1
          afe.remove(formatting_element)
          return
        end

        # Step 8. Ignore the tag if formatting element is not in the scope.
        return unless element_in_scope(Scope::Default, atom)

        # Step 9. This step is omitted because it's just a parse error but no need to return

        # Steps 10-11. Find the furthest block.
        furthest_block : Node? = nil
        oe[fe_index..].each do |e|
          if ParserHelper.special_element?(e)
            furthest_block = e
            break
          end
        end
        if furthest_block.nil?
          e = oe.pop
          while e != formatting_element
            e = oe.pop
          end
          afe.remove(e)
          return
        end

        # Steps 12-13. Find the common ancestor and bookmark node.
        common_ancestor = oe[fe_index - 1]
        bookmark = afe.index(formatting_element)

        # Step 14. The inner loop. Find the last_node to reparent
        last_node = furthest_block
        node = furthest_block
        x = oe.index(node)
        # Step 14.1
        j = 0
        loop do
          # Step 14.2
          j += 1
          # Step 14.3
          x -= 1
          node = oe[x]
          # Step 14.4. Go to the next step if node is formatting element.
          break if node == formatting_element

          # Step 14.5. Remove node from the list of active formatting elements if
          # inner loop counter is greater than three and node is in the list of
          # active formatting elements.
          if (ni = afe.index(node)) && (j > 3) && (ni > -1)
            afe.remove(node)
            # If any element of thie list of active formatting elements is removed,
            # we need to take care whether bookmark should be decremented or not.
            # This is because the value of bookmark may exceed the size of the
            # list by removing elements from the list.
            bookmark -= 1 if ni <= bookmark
            next
          end

          # Step 14.6 Continue the next inner loop if the node is not in the list of
          # active formatting elements.
          if (afe.index(node) == -1)
            oe.remove(node)
            next
          end

          # Step 14.7
          clone = node.clone
          afe[afe.index(node)] = clone
          oe[oe.index(node)] = clone
          node = clone

          # Step 14.8
          bookmark = afe.index(node) + 1 if last_node == furthest_block

          # Step 14.9
          last_node.parent.try &.remove_child(last_node) unless last_node.parent.nil?
          node.append_child(last_node)

          # Step 14.10
          last_node = node
        end

        # Step 15. Reparent last_node to the common ancestor,
        # or for misnested table nodes, to the foster parent.
        last_node.parent.try &.remove_child(last_node)

        case common_ancestor.data_atom
        when Atom::Table, Atom::Tbody, Atom::Tfoot, Atom::Thead, Atom::Tr
          foster_parent(last_node)
        else
          common_ancestor.append_child(last_node)
        end

        # Step 16-18. Reparent nodes from the furthest block's children
        # to a clone of the formatting element.
        clone = formatting_element.clone
        HTML5.reparent_children(clone, furthest_block)
        furthest_block.append_child(clone)

        # Step 19. Fix up the list of active formatting elements.
        if (old_loc = afe.index(formatting_element)) && (old_loc != -1) && (old_loc < bookmark)
          # Move the bookmark with the rest of the list
          bookmark -= 1
        end
        afe.remove(formatting_element)
        afe.insert(bookmark, clone)

        # Step 20. Fix up the stack of open elements.
        oe.remove(formatting_element)
        oe.insert(oe.index(furthest_block) + 1, clone)
      end
    end

    # performs the "any other end tag" algorithm for in_body_im.
    # "Any other end tag" handling from 12.2.6.5 The rules for parsing tokens in foreign content
    # https://html.spec.whatwg.org/multipage/syntax.html#parsing-main-inforeign
    def in_body_end_tag_other(atom : Atom::Atom, tag_name : String)
      (oe.size - 1).downto(0) do |i|
        # Two element nodes have the same tag if they have the same Data (a
        # string-typed field). As an optimization, for common HTML tags, each
        # Data string is assigned a unique, non-zero `Atom` (a UInt32-typed
        # field), since integer comparison is faster than string comparison.
        # Uncommon (custom) tags get a zero `Atom`.
        #
        # The if condition here is equivalent to (oe[i].data == tag_name).
        if (oe[i].data_atom == atom) && ((atom != 0) || (oe[i].data == tag_name))
          self.oe = oe[...i]
          break
        end
        break if ParserHelper.special_element?(oe[i])
      end
    end
  end
end
