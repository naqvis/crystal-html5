require "xpath2"
require "../node"

module HTML5
  class Node
    # Searches this node for XPath *path*. Returns first matched `HTML5::Node` or `nil`
    def xpath(path : String) : Node?
      expr = XPath2.compile(path)
      t = expr.select(HTMLNavigator.new(self, self))
      return get_current_node(t.current.as(XPath2::NodeNavigator)) if t.move_next
      nil
    end

    # Searches this node for XPath *path*. Returns all of the matched `HTML5::Node`
    def xpath_nodes(path : String) : Array(Node)
      elems = Array(Node).new
      expr = XPath2.compile(path)
      if (t = expr.select(HTMLNavigator.new(self, self)))
        while t.move_next
          nav = t.current.as(XPath2::NodeNavigator)
          n = get_current_node(nav)
          # avoid adding duplicating nodes
          if elems.size > 0 && (elems[0] == n || (nav.node_type.attribute? &&
             nav.local_name == elems[0].data && nav.value == elems[0].inner_text))
            next
          end
          elems << n
        end
      end
      elems
    end

    # Searches this node for XPath *path* and restricts the return type to `Bool`.
    def xpath_bool(path : String)
      xpath_evaluate(path).as(Bool)
    end

    # Searches this node for XPath *path* and restricts the return type to `Float64`.
    def xpath_float(path : String)
      xpath_evaluate(path).as(Float64)
    end

    # Searches this node for XPath *path* and restricts the return type to `String`.
    def xpath_bool(path : String)
      xpath_evaluate(path).as(String)
    end

    # Searches this node for XPath *path* and return result with appropriate type
    # `(Bool | Float64 | String | NodeIterator | Nil)`
    def xpath_evaluate(path)
      expr = XPath2.compile(path)
      expr.evaluate(HTMLNavigator.new(self, self))
    end

    # returns the attribute value with specified name. if current node is `element?` it returns
    # the inner text or else it will scan through node attributes and returns the value of attribute matching the `name`
    # returns "" if no attribute is found.
    def attribute_value(name : String)
      return inner_text if type.element? && parent.nil? && name == data
      attr.each do |a|
        return a.val if a.key == name
      end
      ""
    end

    private def get_current_node(n : XPath2::NodeNavigator)
      if n.node_type.attribute?
        child = Node.new(
          type: NodeType::Text,
          data: n.value
        )
        ret = Node.new(
          type: NodeType::Element,
          data: n.local_name
        )
        ret.first_child = child
        ret.last_child = child
        ret
      else
        n.curr
      end
    end
  end

  private class HTMLNavigator
    include XPath2::NodeNavigator

    property curr : Node
    property root : Node
    property attr : Int32

    def initialize(@curr, @root)
      @attr = -1
    end

    def current : Node
      @curr
    end

    def node_type : XPath2::NodeType
      case @curr.type
      when .comment?
        XPath2::NodeType::Comment
      when .text?
        XPath2::NodeType::Text
      when .document?
        XPath2::NodeType::Root
      when .element?
        if @attr != -1
          XPath2::NodeType::Attribute
        else
          XPath2::NodeType::Element
        end
      when .doctype?
        XPath2::NodeType::Root
      else
        raise HTMLException.new("Uknown HTML node type: #{@curr.type}")
      end
    end

    def local_name : String
      return @curr.attr[@attr].key unless @attr == -1
      @curr.data
    end

    def prefix : String
      ""
    end

    def value : String
      case @curr.type
      when .text?, .comment?
        @curr.data
      when .element?
        return @curr.attr[@attr].val unless @attr == -1
        @curr.inner_text
      else
        ""
      end
    end

    def copy : XPath2::NodeNavigator
      n2 = HTMLNavigator.new(@curr, @root)
      n2.attr = @attr.dup
      n2
    end

    def move_to_root
      @curr = @root
    end

    def move_to_parent
      if @attr != -1
        @attr = -1
        true
      elsif (node = @curr.parent)
        @curr = node
        true
      else
        false
      end
    end

    def move_to_next_attribute : Bool
      return false if @attr >= @curr.attr.size - 1
      @attr += 1
      true
    end

    def move_to_child : Bool
      return false unless @attr == -1

      if (node = @curr.first_child)
        @curr = node
        return true
      end
      false
    end

    def move_to_first : Bool
      return false if @attr != -1 || @curr.prev_sibling.nil?
      node = @curr.prev_sibling
      while node
        @curr = node
        node = @curr.prev_sibling
      end
      true
    end

    def to_s(io : IO) : Nil
      io << value
    end

    def move_to_next : Bool
      return false unless @attr == -1

      if (node = @curr.next_sibling)
        @curr = node
        return true
      end
      false
    end

    def move_to_previous : Bool
      return false unless @attr == -1
      if (node = @curr.prev_sibling)
        @curr = node
        return true
      end
      false
    end

    def move_to(nav : XPath2::NodeNavigator) : Bool
      if (node = nav.as?(HTMLNavigator)) && (node.root == @root)
        @curr = node.curr
        @attr = node.attr
        true
      else
        false
      end
    end
  end
end
