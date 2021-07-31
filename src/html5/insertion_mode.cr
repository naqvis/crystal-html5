require "./doctype"

module HTML5
  # An insertion mode (section 12.2.4.1) is the state transition function from
  # a particular state in the HTML5 parser's state machine. It updates the
  # parser's fields depending on parser.token (where ErrorToken means EOF).
  # It returns whether the token was consumed.
  private alias InsertionMode = Proc(Parser, Bool)

  private module ParserHelper
    extend self

    private WHITE_SPACE      = " \t\r\n\f"
    private WHITE_SPACE_NULL = WHITE_SPACE + "\x00"

    # Section 12.2.6.4.1.
    def initial_im(p : Parser) : Bool
      case p.token.type
      when .text?
        p.token.data = p.token.data.lstrip(WHITE_SPACE)
        return true if p.token.data.empty? # it was all whitespace, so ignore it
      when .comment?
        p.doc.append_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      when .doctype?
        n, quirks = parse_doctype(p.token.data)
        p.doc.append_child(n)
        p.quirks = quirks
        p.im = ->before_html_im(Parser)
        return true
      end
      p.quirks = true
      p.im = ->before_html_im(Parser)
      false
    end

    # Section 12.2.6.4.2.
    def before_html_im(p : Parser) : Bool
      case p.token.type
      when .doctype?
        # ignore the token
        return true
      when .text?
        p.token.data = p.token.data.lstrip(WHITE_SPACE)
        return true if p.token.data.empty? # it was all whitespace, so ignore it
      when .start_tag?
        if p.token.data_atom == Atom::Html
          p.add_element
          p.im = ->before_head_im(Parser)
          return true
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Head, Atom::Body, Atom::Html, Atom::Br
          p.parse_implied_token(TokenType::StartTag, Atom::Html, Atom::Html.to_s)
          return false
        else
          # Ignore the token.
          return true
        end
      when .comment?
        p.doc.append_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      end
      p.parse_implied_token(TokenType::StartTag, Atom::Html, Atom::Html.to_s)
      false
    end

    # Section 12.2.6.4.3.
    def before_head_im(p : Parser) : Bool
      case p.token.type
      when .text?
        p.token.data = p.token.data.lstrip(WHITE_SPACE)
        return true if p.token.data.empty? # it was all whitespace, so ignore it
      when .start_tag?
        if p.token.data_atom == Atom::Head
          p.add_element
          p.head = p.top
          p.im = ->in_head_im(Parser)
          return true
        elsif p.token.data_atom == Atom::Html
          return in_body_im(p)
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Head, Atom::Body, Atom::Html, Atom::Br
          p.parse_implied_token(TokenType::StartTag, Atom::Head, Atom::Head.to_s)
          return false
        else
          # Ignore the token
          return true
        end
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      when .doctype?
        # ignore the token
        return true
      else
        false
      end
      p.parse_implied_token(TokenType::StartTag, Atom::Head, Atom::Head.to_s)
      false
    end

    # Section 12.2.6.4.4.
    def in_head_im(p : Parser) : Bool
      case p.token.type
      when .text?
        s = p.token.data.lstrip(WHITE_SPACE)
        if s.bytesize < p.token.data.bytesize
          # Add the initial whitespace to the current node.
          p.add_text(p.token.data[...p.token.data.bytesize - s.bytesize])
          return true if s.empty?
          p.token.data = s
        end
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return in_body_im(p)
        when Atom::Base, Atom::Basefont, Atom::Bgsound, Atom::Link, Atom::Meta
          p.add_element
          p.oe.pop
          p.acknowledge_self_closing_tag
          return true
        when Atom::Noscript
          if p.scripting
            p.parse_generic_raw_text_elements
            return true
          end
          p.add_element
          p.im = ->in_head_no_script_im(Parser)
          # Don't let the tokenizer go into raw text mode when scripting is disabled.
          p.tokenizer.next_is_not_raw_text
          return true
        when Atom::Script, Atom::Title
          p.add_element
          p.set_original_im
          p.im = ->text_im(Parser)
          return true
        when Atom::Noframes, Atom::Style
          p.parse_generic_raw_text_elements
          return true
        when Atom::Head
          # ignore the token.
          return true
        when Atom::Template
          p.add_element
          p.afe << ScopeMarker
          p.frameset_ok = false
          p.im = ->in_template_im(Parser)
          p.template_stack << ->in_template_im(Parser)
          return true
        else
          #
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Head
          p.oe.pop
          p.im = ->after_head_im(Parser)
          return true
        when Atom::Body, Atom::Html, Atom::Br
          p.parse_implied_token(TokenType::EndTag, Atom::Head, Atom::Head.to_s)
          return false
        when Atom::Template
          return true unless p.oe.contains(Atom::Template)
          # TODO: remove this divergence from the HTML5 spec.
          p.generate_implied_end_tags
          (p.oe.size - 1).downto(0) do |i|
            if (n = p.oe[i]) && (n.namespace.empty?) && (n.data_atom == Atom::Template)
              p.oe = p.oe[...i]
              break
            end
          end
          p.clear_active_formatting_elements
          p.template_stack.pop
          p.reset_insertion_mode
          return true
        else
          # Ignore the token
          return true
        end
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      when .doctype?
        # ignore the token
        return true
      else
        false
      end
      p.parse_implied_token(TokenType::EndTag, Atom::Head, Atom::Head.to_s)
      false
    end

    # Section 12.2.6.4.5.
    def in_head_no_script_im(p : Parser) : Bool
      case p.token.type
      when .doctype?
        # ignore the token
        return true
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return in_body_im(p)
        when Atom::Basefont, Atom::Bgsound, Atom::Link, Atom::Meta, Atom::Noframes, Atom::Style
          return in_head_im(p)
        when Atom::Head, Atom::Noscript
          # ignore the token
          return true
        else
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Noscript, Atom::Br
          #
        else
          # Ignore the token.
          return true
        end
      when .text?
        s = p.token.data.lstrip(WHITE_SPACE)
        return in_head_im(p) if s.empty? # it was all whitespace
      when .comment?
        return in_head_im(p)
      else
        #
      end
      p.oe.pop
      raise HTMLException.new("the current node will be a head element.") unless p.top.data_atom == Atom::Head
      p.im = ->in_head_im(Parser)
      return true if p.token.data_atom == Atom::Noscript
      false
    end

    # Section 12.2.6.4.6.
    def after_head_im(p : Parser) : Bool
      case p.token.type
      when .text?
        s = p.token.data.lstrip(WHITE_SPACE)
        if s.bytesize < p.token.data.bytesize
          # Add the initial whitespace to the current node.
          p.add_text(p.token.data[...p.token.data.bytesize - s.bytesize])
          return true if s.empty?
          p.token.data = s
        end
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return in_body_im(p)
        when Atom::Body
          p.add_element
          p.frameset_ok = false
          p.im = ->in_body_im(Parser)
          return true
        when Atom::Frameset
          p.add_element
          p.im = ->in_frameset_im(Parser)
          return true
        when Atom::Base, Atom::Basefont, Atom::Bgsound, Atom::Link, Atom::Meta, Atom::Noframes, Atom::Script, Atom::Style, Atom::Template, Atom::Title
          if (h = p.head)
            p.oe << h
            begin
              return in_head_im(p)
            ensure
              p.oe.remove(h)
            end
          end
        when Atom::Head
          # Ignore the token
          return true
        else
          #
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Body, Atom::Html, Atom::Br
          # Drop down to creating an implied <body> tag.
        when Atom::Template
          return in_head_im(p)
        else
          # Ignore the token
          return true
        end
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      when .doctype?
        # ignore the token
        return true
      else
        false
      end
      p.parse_implied_token(TokenType::StartTag, Atom::Body, Atom::Body.to_s)
      p.frameset_ok = true
      false
    end

    # copies attributes of src not found on dst to dst
    def copy_attributes(dst : Node, src : Token)
      return if src.attr.size == 0
      attr = Hash(String, String).new
      dst.attr.each do |t|
        attr[t.key] = t.val
      end

      src.attr.each do |t|
        unless attr.has_key?(t.key)
          dst.attr << t
          attr[t.key] = t.val
        end
      end
    end

    # Section 12.2.6.4.7.
    def in_body_im(p : Parser) : Bool
      case p.token.type
      when .text?
        d = p.token.data
        if (n = p.oe.top)
          case n.data_atom
          when Atom::Pre, Atom::Listing
            if n.first_child.nil?
              # Ignore a newline at the start of a <pre> block.
              d = d[1..] if !d.empty? && d[0] == '\r'
              d = d[1..] if !d.empty? && d[0] == '\n'
            end
          else
            #
          end
        end
        d = d.gsub("\x00", "")
        return true if d.empty?
        p.reconstruct_active_formatting_elements
        p.add_text(d)
        if p.frameset_ok && !d.lstrip(WHITE_SPACE).empty?
          # There were non-whitespace characters inserted.
          p.frameset_ok = false
        end
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return true if p.oe.contains(Atom::Template)
          copy_attributes(p.oe[0], p.token)
        when Atom::Base, Atom::Basefont, Atom::Bgsound, Atom::Link, Atom::Meta, Atom::Noframes, Atom::Script, Atom::Style, Atom::Template, Atom::Title
          return in_head_im(p)
        when Atom::Body
          return true if p.oe.contains(Atom::Template)
          if p.oe.size >= 2
            body = p.oe[1]
            if body.type.element? && body.data_atom == Atom::Body
              p.frameset_ok = false
              copy_attributes(body, p.token)
            end
          end
        when Atom::Frameset
          if !p.frameset_ok || p.oe.size < 2 || p.oe[1].data_atom != Atom::Body
            # Ignore the token
            return true
          end
          body = p.oe[1]
          if (parent = body.parent)
            parent.remove_child(body)
          end
          p.oe = p.oe[...1]
          p.add_element
          p.im = ->in_frameset_im(Parser)
          return true
        when Atom::Address, Atom::Article, Atom::Aside, Atom::Blockquote, Atom::Center, Atom::Details, Atom::Dialog,
             Atom::Dir, Atom::Div, Atom::Dl, Atom::Fieldset, Atom::Figcaption, Atom::Figure, Atom::Footer, Atom::Header,
             Atom::Hgroup, Atom::Main, Atom::Menu, Atom::Nav, Atom::Ol, Atom::P, Atom::Section, Atom::Summary, Atom::Ul
          p.pop_until(Scope::Button, Atom::P)
          p.add_element
        when Atom::H1, Atom::H2, Atom::H3, Atom::H4, Atom::H5, Atom::H6
          p.pop_until(Scope::Button, Atom::P)
          n = p.top
          p.oe.pop if {Atom::H1, Atom::H2, Atom::H3, Atom::H4, Atom::H5, Atom::H6}.includes?(n.data_atom)
          p.add_element
        when Atom::Pre, Atom::Listing
          p.pop_until(Scope::Button, Atom::P)
          p.add_element
          # The newline, if any, will be dealt with by the TextToken case
          p.frameset_ok = false
        when Atom::Form
          return true if !p.form.nil? && !p.oe.contains(Atom::Template) # Ignore the token
          p.pop_until(Scope::Button, Atom::P)
          p.add_element
          p.form = p.top unless p.oe.contains(Atom::Template)
        when Atom::Li
          p.frameset_ok = false
          (p.oe.size - 1).downto(0) do |i|
            node = p.oe[i]
            case node.data_atom
            when Atom::Li
              p.oe = p.oe[...i]
            when Atom::Address, Atom::Div, Atom::P
              next
            else
              next unless special_element?(node)
            end
            break
          end
          p.pop_until(Scope::Button, Atom::P)
          p.add_element
        when Atom::Dd, Atom::Dt
          p.frameset_ok = false
          (p.oe.size - 1).downto(0) do |i|
            node = p.oe[i]
            case node.data_atom
            when Atom::Dd, Atom::Dt
              p.oe = p.oe[...i]
            when Atom::Address, Atom::Div, Atom::P
              next
            else
              next unless special_element?(node)
            end
            break
          end
          p.pop_until(Scope::Button, Atom::P)
          p.add_element
        when Atom::Plaintext
          p.pop_until(Scope::Button, Atom::P)
          p.add_element
        when Atom::Button
          p.pop_until(Scope::Default, Atom::Button)
          p.reconstruct_active_formatting_elements
          p.add_element
          p.frameset_ok = false
        when Atom::A
          i = p.afe.size - 1
          while i >= 0 && !p.afe[i].type.scope_marker?
            if (n = p.afe[i]) && n.type.element? && (n.data_atom == Atom::A)
              p.in_body_end_tag_formatting(Atom::A, "a")
              p.oe.remove(n)
              p.afe.remove(n)
              break
            end
            i -= 1
          end
          p.reconstruct_active_formatting_elements
          p.add_formatting_element
        when Atom::B, Atom::Big, Atom::Code, Atom::Em, Atom::Font, Atom::I, Atom::S, Atom::Small, Atom::Strike, Atom::Strong, Atom::Tt, Atom::U
          p.reconstruct_active_formatting_elements
          p.add_formatting_element
        when Atom::Nobr
          p.reconstruct_active_formatting_elements
          if p.element_in_scope(Scope::Default, Atom::Nobr)
            p.in_body_end_tag_formatting(Atom::Nobr, "nobr")
            p.reconstruct_active_formatting_elements
          end
          p.add_formatting_element
        when Atom::Applet, Atom::Marquee, Atom::Object
          p.reconstruct_active_formatting_elements
          p.add_element
          p.afe << ScopeMarker
          p.frameset_ok = false
        when Atom::Table
          p.pop_until(Scope::Button, Atom::P) unless p.quirks
          p.add_element
          p.frameset_ok = false
          p.im = ->in_table_im(Parser)
          return true
        when Atom::Area, Atom::Br, Atom::Embed, Atom::Img, Atom::Input, Atom::Keygen, Atom::Wbr
          p.reconstruct_active_formatting_elements
          p.add_element
          p.oe.pop
          p.acknowledge_self_closing_tag
          if p.token.data_atom == Atom::Input
            p.token.attr.each do |t|
              if t.key == "type" && t.val.downcase == "hidden"
                # Skip setting frameset_ok = false
                return true
              end
            end
          end
          p.frameset_ok = false
        when Atom::Param, Atom::Source, Atom::Track
          p.add_element
          p.oe.pop
          p.acknowledge_self_closing_tag
        when Atom::Hr
          p.pop_until(Scope::Button, Atom::P)
          p.add_element
          p.oe.pop
          p.acknowledge_self_closing_tag
          p.frameset_ok = false
        when Atom::Image
          p.token.data_atom = Atom::Img
          p.token.data = Atom::Img.to_s
          return false
        when Atom::Textarea
          p.add_element
          p.set_original_im
          p.frameset_ok = false
          p.im = ->text_im(Parser)
        when Atom::Xmp
          p.pop_until(Scope::Button, Atom::P)
          p.reconstruct_active_formatting_elements
          p.frameset_ok = false
          p.parse_generic_raw_text_elements
        when Atom::Iframe
          p.frameset_ok = false
          p.parse_generic_raw_text_elements
        when Atom::Noscript
          if p.scripting
            p.parse_generic_raw_text_elements
            return true
          end
          p.reconstruct_active_formatting_elements
          p.add_element
          # dont' let the tokenizer go into raw text mode when scripting is disabled
          p.tokenizer.next_is_not_raw_text
        when Atom::Select
          p.reconstruct_active_formatting_elements
          p.add_element
          p.frameset_ok = false
          p.im = ->in_select_im(Parser)
          return true
        when Atom::Optgroup, Atom::Option
          p.oe.pop if p.top.data_atom == Atom::Option
          p.reconstruct_active_formatting_elements
          p.add_element
        when Atom::Rb, Atom::Rtc
          p.generate_implied_end_tags if p.element_in_scope(Scope::Default, Atom::Ruby)
          p.add_element
        when Atom::Rp, Atom::Rt
          p.generate_implied_end_tags("rtc") if p.element_in_scope(Scope::Default, Atom::Ruby)
          p.add_element
        when Atom::Math, Atom::Svg
          p.reconstruct_active_formatting_elements
          if p.token.data_atom == Atom::Math
            adjust_attribute_names(p.token.attr, MATHML_ATTRIBUTE_ADJUSTMENTS)
          else
            adjust_attribute_names(p.token.attr, SVG_ATTRIBUTE_ADJUSTMENTS)
          end
          adjust_foreign_attributes(p.token.attr)
          p.add_element
          p.top.namespace = p.token.data
          if p.has_self_closing_token
            p.oe.pop
            p.acknowledge_self_closing_tag
          end
          return true
        when Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Frame, Atom::Head, Atom::Tbody,
             Atom::Td, Atom::Tfoot, Atom::Th, Atom::Thead, Atom::Tr
          # Ignore the token
        else
          p.reconstruct_active_formatting_elements
          p.add_element
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Body
          p.im = ->after_body_im(Parser) if p.element_in_scope(Scope::Default, Atom::Body)
        when Atom::Html
          if p.element_in_scope(Scope::Default, Atom::Body)
            p.parse_implied_token(TokenType::EndTag, Atom::Body, Atom::Body.to_s)
            return false
          end
          return true
        when Atom::Address, Atom::Article, Atom::Aside, Atom::Blockquote, Atom::Button, Atom::Center,
             Atom::Details, Atom::Dialog, Atom::Dir, Atom::Div, Atom::Dl, Atom::Fieldset, Atom::Figcaption,
             Atom::Figure, Atom::Footer, Atom::Header, Atom::Hgroup, Atom::Listing, Atom::Main, Atom::Menu,
             Atom::Nav, Atom::Ol, Atom::Pre, Atom::Section, Atom::Summary, Atom::Ul
          p.pop_until(Scope::Default, p.token.data_atom)
        when Atom::Form
          if p.oe.contains(Atom::Template)
            i = p.index_of_element_in_scope(Scope::Default, Atom::Form)
            return true if i == -1 # Ignore the token
            p.generate_implied_end_tags
            return true unless p.oe[i].data_atom == Atom::Form # Ignore the token
            p.pop_until(Scope::Default, Atom::Form)
          else
            node = p.form
            p.form = nil
            i = p.index_of_element_in_scope(Scope::Default, Atom::Form)
            return true if node.nil? || i == -1 || p.oe[i] != node # Ignore the token
            p.generate_implied_end_tags
            p.oe.remove(node)
          end
        when Atom::P
          unless p.element_in_scope(Scope::Button, Atom::P)
            p.parse_implied_token(TokenType::StartTag, Atom::P, Atom::P.to_s)
          end
          p.pop_until(Scope::Button, Atom::P)
        when Atom::Li
          p.pop_until(Scope::ListItem, Atom::Li)
        when Atom::Dd, Atom::Dt
          p.pop_until(Scope::Default, p.token.data_atom)
        when Atom::H1, Atom::H2, Atom::H3, Atom::H4, Atom::H5, Atom::H6
          p.pop_until(Scope::Default, Atom::H1, Atom::H2, Atom::H3, Atom::H4, Atom::H5, Atom::H6)
        when Atom::A, Atom::B, Atom::Big, Atom::Code, Atom::Em, Atom::Font, Atom::I, Atom::Nobr, Atom::S,
             Atom::Small, Atom::Strike, Atom::Strong, Atom::Tt, Atom::U
          p.in_body_end_tag_formatting(p.token.data_atom, p.token.data)
        when Atom::Applet, Atom::Marquee, Atom::Object
          if p.pop_until(Scope::Default, p.token.data_atom)
            p.clear_active_formatting_elements
          end
        when Atom::Br
          p.token.type = TokenType::StartTag
          return false
        when Atom::Template
          return in_head_im(p)
        else
          p.in_body_end_tag_other(p.token.data_atom, p.token.data)
        end
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
      when .error?
        # TODO: remove this divergence from the HTML5 spec.
        if p.template_stack.size > 0
          p.im = ->in_template_im(Parser)
          return false
        end
        p.oe.each do |e|
          case e.data_atom
          when Atom::Dd, Atom::Dt, Atom::Li, Atom::Optgroup, Atom::Option, Atom::P, Atom::Rb, Atom::Rp, Atom::Rt,
               Atom::Rtc, Atom::Tbody, Atom::Td, Atom::Tfoot, Atom::Th, Atom::Thead, Atom::Tr, Atom::Body, Atom::Html
            #
          else
            return true
          end
        end
      else
        true
      end
      true
    end

    # Section 12.2.6.4.8.
    def text_im(p : Parser) : Bool
      case p.token.type
      when .error?
        p.oe.pop
      when .text?
        d = p.token.data
        if (n = p.oe.top) && (n.data_atom == Atom::Textarea && n.first_child.nil?)
          # Ignore a newline at the start of a <pre> block.
          d = d[1..] if !d.empty? && d[0] == '\r'
          d = d[1..] if !d.empty? && d[0] == '\n'
        end
        return true if d.empty?
        p.add_text(d)
        return true
      when .end_tag?
        p.oe.pop
      else
      end
      if (orig = p.original_im)
        p.im = orig
      end
      p.original_im = nil
      p.token.type.end_tag?
    end

    # Section 12.2.6.4.9
    def in_table_im(p : Parser) : Bool
      case p.token.type
      when .text?
        p.token.data = p.token.data.gsub("\x00", "")
        if {Atom::Table, Atom::Tbody, Atom::Tfoot, Atom::Thead, Atom::Tr}.includes?(p.oe.top.try &.data_atom)
          if p.token.data.strip(WHITE_SPACE).empty?
            p.add_text(p.token.data)
            return true
          end
        end
      when .start_tag?
        case p.token.data_atom
        when Atom::Caption
          p.clear_stack_to_context(Scope::Table)
          p.afe << ScopeMarker
          p.add_element
          p.im = ->in_caption_im(Parser)
          return true
        when Atom::Colgroup
          p.clear_stack_to_context(Scope::Table)
          p.add_element
          p.im = ->in_column_group_im(Parser)
          return true
        when Atom::Col
          p.parse_implied_token(TokenType::StartTag, Atom::Colgroup, Atom::Colgroup.to_s)
          return false
        when Atom::Tbody, Atom::Tfoot, Atom::Thead
          p.clear_stack_to_context(Scope::Table)
          p.add_element
          p.im = ->in_table_body_im(Parser)
          return true
        when Atom::Td, Atom::Th, Atom::Tr
          p.parse_implied_token(TokenType::StartTag, Atom::Tbody, Atom::Tbody.to_s)
          return false
        when Atom::Table
          if p.pop_until(Scope::Table, Atom::Table)
            p.reset_insertion_mode
            return false
          end
          # ignore the token
          return true
        when Atom::Style, Atom::Script, Atom::Template
          return in_head_im(p)
        when Atom::Input
          p.token.attr.each do |t|
            if t.key == "type" && t.val.downcase == "hidden"
              p.add_element
              p.oe.pop
              return true
            end
          end
          # Otherwise drop down to the down to the default action
        when Atom::Form
          return true if p.oe.contains(Atom::Template) || !p.form.nil?
          p.add_element
          p.form = p.oe.pop
        when Atom::Select
          p.reconstruct_active_formatting_elements
          if {Atom::Table, Atom::Tbody, Atom::Tfoot, Atom::Thead, Atom::Tr}.includes?(p.top.data_atom)
            p.foster_parenting = true
          end
          p.add_element
          p.foster_parenting = false
          p.frameset_ok = false
          p.im = ->in_select_in_table_im(Parser)
          return true
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Table
          if p.pop_until(Scope::Table, Atom::Table)
            p.reset_insertion_mode
            return true
          end
          return true # ignore the token
        when Atom::Body, Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Html, Atom::Tbody,
             Atom::Td, Atom::Tfoot, Atom::Th, Atom::Thead, Atom::Tr
          # ignore the token
          return true
        when Atom::Template
          return in_head_im(p)
        else
          #
        end
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      when .doctype?
        # ignore the token
        return true
      when .error?
        return in_body_im(p)
      else
        #
      end
      p.foster_parenting = true
      begin
        in_body_im(p)
      ensure
        p.foster_parenting = false
      end
    end

    # Section 12.2.6.4.11.
    def in_caption_im(p : Parser) : Bool
      case p.token.type
      when .start_tag?
        case p.token.data_atom
        when Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Tbody, Atom::Td,
             Atom::Tfoot, Atom::Thead, Atom::Tr
          return true unless p.pop_until(Scope::Table, Atom::Caption) # ignore the token
          p.clear_active_formatting_elements
          p.im = ->in_table_im(Parser)
          return false
        when Atom::Select
          p.reconstruct_active_formatting_elements
          p.add_element
          p.frameset_ok = false
          p.im = ->in_select_in_table_im(Parser)
          return true
        else
          #
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Caption
          if p.pop_until(Scope::Table, Atom::Caption)
            p.clear_active_formatting_elements
            p.im = ->in_table_im(Parser)
          end
          return true
        when Atom::Table
          return true unless p.pop_until(Scope::Table, Atom::Caption)
          p.clear_active_formatting_elements
          p.im = ->in_table_im(Parser)
          return false
        when Atom::Body, Atom::Col, Atom::Colgroup, Atom::Html, Atom::Tbody, Atom::Td,
             Atom::Tfoot, Atom::Th, Atom::Thead, Atom::Tr
          # ignore the token
          return true
        else
          #
        end
      else
        #
      end
      in_body_im(p)
    end

    # Section 12.2.6.4.12
    def in_column_group_im(p : Parser) : Bool
      case p.token.type
      when .text?
        s = p.token.data.lstrip(WHITE_SPACE)
        if s.bytesize < p.token.data.bytesize
          # Add the initial whitespace to the current node.
          p.add_text(p.token.data[...p.token.data.bytesize - s.bytesize])
          return true if s.empty?
          p.token.data = s
        end
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      when .doctype?
        # ignore the token
        return true
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return in_body_im(p)
        when Atom::Col
          p.add_element
          p.oe.pop
          p.acknowledge_self_closing_tag
          return true
        when Atom::Template
          return in_head_im(p)
        else
          #
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Colgroup
          if p.oe.top.try &.data_atom == Atom::Colgroup
            p.oe.pop
            p.im = ->in_table_im(Parser)
          end
          return true
        when Atom::Col
          # Ignore the token
          return true
        when Atom::Template
          return in_head_im(p)
        else
          #
        end
      when .error?
        return in_body_im(p)
      else
        #
      end
      return true unless p.oe.top.try &.data_atom == Atom::Colgroup
      p.oe.pop
      p.im = ->in_table_im(Parser)
      false
    end

    # Section 12.2.6.4.13.
    def in_table_body_im(p : Parser) : Bool
      case p.token.type
      when .start_tag?
        case p.token.data_atom
        when Atom::Tr
          p.clear_stack_to_context(Scope::TableBody)
          p.add_element
          p.im = ->in_row_im(Parser)
          return true
        when Atom::Td, Atom::Th
          p.parse_implied_token(TokenType::StartTag, Atom::Tr, Atom::Tr.to_s)
          return false
        when Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Tbody, Atom::Tfoot, Atom::Thead
          if p.pop_until(Scope::Table, Atom::Tbody, Atom::Thead, Atom::Tfoot)
            p.im = ->in_table_im(Parser)
            return false
          end
          # ignore the token
          return true
        else
          #
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Tbody, Atom::Tfoot, Atom::Thead
          if p.element_in_scope(Scope::Table, p.token.data_atom)
            p.clear_stack_to_context(Scope::TableBody)
            p.oe.pop
            p.im = ->in_table_im(Parser)
          end
          return true
        when Atom::Table
          if p.pop_until(Scope::Table, Atom::Tbody, Atom::Thead, Atom::Tfoot)
            p.im = ->in_table_im(Parser)
            return false
          end
          # ignore the token
          return true
        when Atom::Body, Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Html, Atom::Td, Atom::Th, Atom::Tr
          # ignore the token
          return true
        else
          #
        end
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      end
      in_table_im(p)
    end

    # Section 12.2.6.4.14.
    def in_row_im(p : Parser) : Bool
      case p.token.type
      when .start_tag?
        case p.token.data_atom
        when Atom::Td, Atom::Th
          p.clear_stack_to_context(Scope::TableRow)
          p.add_element
          p.afe << ScopeMarker
          p.im = ->in_cell_im(Parser)
          return true
        when Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Tbody, Atom::Tfoot, Atom::Thead, Atom::Tr
          if p.pop_until(Scope::Table, Atom::Tr)
            p.im = ->in_table_body_im(Parser)
            return false
          end
          # ignore the token
          return true
        else
          #
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Tr
          if p.pop_until(Scope::Table, Atom::Tr)
            p.im = ->in_table_body_im(Parser)
            return true
          end
          # ignore the token
          return true
        when Atom::Table
          if p.pop_until(Scope::Table, Atom::Tr)
            p.im = ->in_table_body_im(Parser)
            return false
          end
          # ignore the token
          return true
        when Atom::Tbody, Atom::Tfoot, Atom::Thead
          if p.element_in_scope(Scope::Table, p.token.data_atom)
            p.parse_implied_token(TokenType::EndTag, Atom::Tr, Atom::Tr.to_s)
            return false
          end
          # ignore the token
          return true
        when Atom::Body, Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Html, Atom::Td, Atom::Th
          # ignore the token
          return true
        end
      else
        #
      end
      in_table_im(p)
    end

    # Section 12.2.6.4.15.
    def in_cell_im(p : Parser) : Bool
      case p.token.type
      when .start_tag?
        case p.token.data_atom
        when Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Tbody, Atom::Td, Atom::Tfoot, Atom::Th, Atom::Thead, Atom::Tr
          if p.pop_until(Scope::Table, Atom::Td, Atom::Th)
            # Close the cell and reprocess
            p.clear_active_formatting_elements
            p.im = ->in_row_im(Parser)
            return false
          end
          # ignore the token
          return true
        when Atom::Select
          p.reconstruct_active_formatting_elements
          p.add_element
          p.frameset_ok = false
          p.im = ->in_select_in_table_im(Parser)
          return true
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Td, Atom::Th
          return true unless p.pop_until(Scope::Table, p.token.data_atom) # ignore the token
          p.clear_active_formatting_elements
          p.im = ->in_row_im(Parser)
          return true
        when Atom::Body, Atom::Caption, Atom::Col, Atom::Colgroup, Atom::Html
          # ignore the token
          return true
        when Atom::Table, Atom::Tbody, Atom::Tfoot, Atom::Thead, Atom::Tr
          return true unless p.element_in_scope(Scope::Table, p.token.data_atom) # ignore the token
          # Close the cell and reprocess
          if p.pop_until(Scope::Table, Atom::Td, Atom::Th)
            p.clear_active_formatting_elements
          end
          p.im = ->in_row_im(Parser)
          return false
        end
      end
      in_body_im(p)
    end

    # Section 12.2.6.4.16.
    def in_select_im(p : Parser) : Bool
      case p.token.type
      when .text?
        p.add_text(p.token.data.gsub("\x00", ""))
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return in_body_im(p)
        when Atom::Option
          p.oe.pop if p.top.data_atom == Atom::Option
          p.add_element
        when Atom::Optgroup
          p.oe.pop if p.top.data_atom == Atom::Option
          p.oe.pop if p.top.data_atom == Atom::Optgroup
          p.add_element
        when Atom::Select
          return true unless p.pop_until(Scope::Select, Atom::Select) # ignore the token
          p.reset_insertion_mode
        when Atom::Input, Atom::Keygen, Atom::Textarea
          if p.element_in_scope(Scope::Select, Atom::Select)
            p.parse_implied_token(TokenType::EndTag, Atom::Select, Atom::Select.to_s)
            return false
          end
          # In order to properly ignore <textarea>, we need to change the tokenizer mode
          p.tokenizer.next_is_not_raw_text
          # ignore the token
          return true
        when Atom::Script, Atom::Template
          return in_head_im(p)
        end
      when .end_tag?
        case p.token.data_atom
        when Atom::Option
          p.oe.pop if p.top.data_atom == Atom::Option
        when Atom::Optgroup
          i = p.oe.size - 1
          i -= 1 if p.oe[i].data_atom == Atom::Option
          p.oe = p.oe[...i] if p.oe[i].data_atom == Atom::Optgroup
        when Atom::Select
          return true unless p.pop_until(Scope::Select, Atom::Select) # ignore the token
          p.reset_insertion_mode
        when Atom::Template
          return in_head_im(p)
        end
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
      when .doctype?
        # ignore the token
        return true
      when .error?
        return in_body_im(p)
      end
      true
    end

    # Section 12.2.6.4.17.
    def in_select_in_table_im(p : Parser) : Bool
      case p.token.type
      when .start_tag?, .end_tag?
        case p.token.data_atom
        when Atom::Caption, Atom::Table, Atom::Tbody, Atom::Tfoot, Atom::Thead, Atom::Tr, Atom::Td, Atom::Th
          if p.token.type.end_tag? && !p.element_in_scope(Scope::Table, p.token.data_atom)
            # Ignore the token
            return true
          end
          # This is like p.pop_until(Scope::Select, Atom::Select), but it also
          # matches <math select>, not just <select>. Matching the MathML
          # tag is arguably incorrect (conceptually), but it mimics what
          # Chromium does.
          (p.oe.size - 1).downto(0) do |i|
            if (n = p.oe[i]) && (n.data_atom == Atom::Select)
              p.oe = p.oe[...i]
              break
            end
          end
          p.reset_insertion_mode
          return false
        end
      end
      in_select_im(p)
    end

    # Section 12.2.6.4.18.
    def in_template_im(p : Parser) : Bool
      case p.token.type
      when .text?, .comment?, .doctype?
        return in_body_im(p)
      when .start_tag?
        case p.token.data_atom
        when Atom::Base, Atom::Basefont, Atom::Bgsound, Atom::Link, Atom::Meta, Atom::Noframes,
             Atom::Script, Atom::Style, Atom::Template, Atom::Title
          return in_head_im(p)
        when Atom::Caption, Atom::Colgroup, Atom::Tbody, Atom::Tfoot, Atom::Thead
          p.template_stack.pop
          p.template_stack << ->in_table_im(Parser)
          p.im = ->in_table_im(Parser)
          return false
        when Atom::Col
          p.template_stack.pop
          p.template_stack << ->in_column_group_im(Parser)
          p.im = ->in_column_group_im(Parser)
          return false
        when Atom::Tr
          p.template_stack.pop
          p.template_stack << ->in_table_body_im(Parser)
          p.im = ->in_table_body_im(Parser)
          return false
        when Atom::Td, Atom::Th
          p.template_stack.pop
          p.template_stack << ->in_row_im(Parser)
          p.im = ->in_row_im(Parser)
          return false
        else
          p.template_stack.pop
          p.template_stack << ->in_body_im(Parser)
          p.im = ->in_body_im(Parser)
          return false
        end
      when .end_tag?
        if p.token.data_atom == Atom::Template
          return in_head_im(p)
        else
          return true # Ignore the token
        end
      when .error?
        return true unless p.oe.contains(Atom::Template) # ignore the token

        # TODO: remove this divergence from the HTML5 spec.
        p.generate_implied_end_tags
        (p.oe.size - 1).downto(0) do |i|
          if (n = p.oe[i]) && (n.namespace.empty? && n.data_atom == Atom::Template)
            p.oe = p.oe[...i]
            break
          end
        end
        p.clear_active_formatting_elements
        p.template_stack.pop
        p.reset_insertion_mode
        return false
      else
        false
      end
      false
    end

    # Section 12.2.6.4.19.
    def after_body_im(p : Parser) : Bool
      case p.token.type
      when .error?
        # stop parsing
        return true
      when .text?
        s = p.token.data.lstrip(WHITE_SPACE)
        return in_body_im(p) if s.empty? # It was all whitespace
      when .start_tag?
        return in_body_im(p) if p.token.data_atom == Atom::Html
      when .end_tag?
        if p.token.data_atom == Atom::Html
          unless p.fragment
            p.im = ->after_after_body_im(Parser)
          end
          return true
        end
      when .comment?
        # The comment is attached to the <html> element.
        if p.oe.size < 1 || p.oe[0].data_atom != Atom::Html
          raise HTMLException.new("bad parser state: <html> element not found, in the after-body insertion mode")
        end
        p.oe[0].append_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      end
      p.im = ->in_body_im(Parser)
      false
    end

    # Section 12.2.6.4.20.
    def in_frameset_im(p : Parser) : Bool
      case p.token.type
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
      when .text?
        # Ignore all text but whitespace
        s = String.build do |sb|
          p.token.data.each_char do |c|
            sb << c if {' ', '\t', '\n', '\f', '\r'}.includes?(c)
          end
        end
        p.add_text(s) unless s.empty?
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return in_body_im(p)
        when Atom::Frameset
          p.add_element
        when Atom::Frame
          p.add_element
          p.oe.pop
          p.acknowledge_self_closing_tag
        when Atom::Noframes
          return in_head_im(p)
        end
      when .end_tag?
        if p.token.data_atom == Atom::Frameset
          unless p.oe.top.try &.data_atom == Atom::Html
            p.oe.pop
            unless p.oe.top.try &.data_atom == Atom::Frameset
              p.im = ->after_frameset_im(Parser)
              return true
            end
          end
        end
      else
        # Ignore the token
      end
      true
    end

    # Section 12.2.6.4.21.
    def after_frameset_im(p : Parser) : Bool
      case p.token.type
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
      when .text?
        # Ignore all text but whitespace
        s = String.build do |sb|
          p.token.data.each_char do |c|
            sb << c if {' ', '\t', '\n', '\f', '\r'}.includes?(c)
          end
        end
        p.add_text(s) unless s.empty?
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return in_body_im(p)
        when Atom::Noframes
          return in_head_im(p)
        else
          #
        end
      when .end_tag?
        if p.token.data_atom == Atom::Html
          p.im = ->after_after_frameset_im(Parser)
          return true
        end
      else
        # Ignore the token
      end
      true
    end

    # Section 12.2.6.4.22.
    def after_after_body_im(p : Parser) : Bool
      case p.token.type
      when .error?
        # stop parsing
        return true
      when .text?
        if s = p.token.data.lstrip(WHITE_SPACE)
          return in_body_im(p) if s.empty?
        end
      when .start_tag?
        return in_body_im(p) if p.token.data_atom == Atom::Html
      when .comment?
        p.doc.append_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
        return true
      when .doctype?
        return in_body_im(p)
      end
      p.im = ->in_body_im(Parser)
      false
    end

    # Section 12.2.6.4.23.
    def after_after_frameset_im(p : Parser) : Bool
      case p.token.type
      when .comment?
        p.doc.append_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
      when .text?
        # Ignore all text but whitespace
        s = String.build do |sb|
          p.token.data.each_char do |c|
            sb << c if {' ', '\t', '\n', '\f', '\r'}.includes?(c)
          end
        end
        unless s.empty?
          p.token.data = s
          return in_body_im(p)
        end
      when .start_tag?
        case p.token.data_atom
        when Atom::Html
          return in_body_im(p)
        when Atom::Noframes
          return in_head_im(p)
        end
      when .doctype?
        return in_body_im(p)
      else
        # ignore the token
      end
      true
    end

    # Section 12.2.6.5
    def parse_foreign_content(p : Parser) : Bool
      case p.token.type
      when .text?
        p.frameset_ok = p.token.data.lstrip(WHITE_SPACE_NULL).empty? if p.frameset_ok
        p.token.data = p.token.data.gsub("\x00", "\ufffd")
        p.add_text(p.token.data)
      when .comment?
        p.add_child(Node.new(
          type: NodeType::Comment,
          data: p.token.data
        ))
      when .start_tag?
        unless p.fragment
          b = BREAKOUT.fetch(p.token.data, false)
          if p.token.data_atom == Atom::Font
            p.token.attr.each do |attr|
              if {"color", "face", "size"}.includes?(attr.key)
                b = true
                break
              end
            end
          end
          if b
            (p.oe.size - 1).downto(0) do |i|
              n = p.oe[i]
              if n.namespace.empty? || html_integration_point(n) || mathml_text_integration_point(n)
                p.oe = p.oe[...i + 1]
                break
              end
            end
            return false
          end
        end
        if (current = p.adjusted_current_node)
          case current.namespace
          when "math"
            adjust_attribute_names(p.token.attr, MATHML_ATTRIBUTE_ADJUSTMENTS)
          when "svg"
            # Adjust SVG tag names. The tokenizer lower-cases tag names, but
            # SVG wants e.g. "foreignObject" with a capital second "O".
            if (x = SVG_TAG_NAMED_ADJUSTMENTS[p.token.data]?) && !x.empty?
              p.token.data_atom = Atom.lookup(x.to_slice)
              p.token.data = x
            end
            adjust_attribute_names(p.token.attr, SVG_ATTRIBUTE_ADJUSTMENTS)
          else
            raise HTMLException.new("bad parser state: unexpected namespace [#{current.namespace}]")
          end
          adjust_foreign_attributes(p.token.attr)
          namespace = current.namespace
          p.add_element
          p.top.namespace = namespace
          unless namespace.empty?
            # Don't let the tokenizer go into raw text mode in foreign content
            # (e.g in an SVG <title> tag).
            p.tokenizer.next_is_not_raw_text
          end
          if p.has_self_closing_token
            p.oe.pop
            p.acknowledge_self_closing_tag
          end
        end
      when .end_tag?
        (p.oe.size - 1).downto(0) do |i|
          return p.im.call(p) if p.oe[i].namespace.empty?
          if p.token.data.compare(p.oe[i].data, case_insensitive: true, options: Unicode::CaseOptions::Fold) == 0
            p.oe = p.oe[...i]
            break
          end
        end
        true
      else
        # Ignore the token
      end
      true
    end
  end
end
