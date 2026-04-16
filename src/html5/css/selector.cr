require "../node"

module HTML5
  class Node
    # Searches this node for CSS Selector *expression*. Returns all of the matched `HTML5::Node`
    def css(expression : String) : Array(Node)
      comp = CSS.compile(expression, scope_node: self)
      comp.select(self)
    end
  end
end

module CSS
  class Selector
    def initialize(@selector_group = Array(Select).new)
    end

    def select(n : HTML5::Node) : Array(HTML5::Node)
      matched = [] of HTML5::Node
      @selector_group.each do |sel|
        matched = sel.select(n, matched)
      end
      matched
    end
  end

  private module Select
    abstract def select(n : HTML5::Node, selected = [] of HTML5::Node) : Array(HTML5::Node)
  end

  private class SelectorImpl
    include Select
    getter combs : Array(CombinatorSelector)

    def initialize(@sel_seq : SelectorSequence, @combs = Array(CombinatorSelector).new)
    end

    def select(n : HTML5::Node, selected = [] of HTML5::Node) : Array(HTML5::Node)
      selected = @sel_seq.select(n, selected)
      @combs.each do |comb|
        comb_matched = [] of HTML5::Node
        selected.each do |m|
          comb_matched = comb.select(m, comb_matched)
        end
        selected = comb_matched
      end
      selected
    end
  end

  private module Matcher
    abstract def matches(n : HTML5::Node) : Bool
  end

  private struct MatcherFunc
    include Matcher

    def initialize(@f : (HTML5::Node) -> Bool)
    end

    def matches(n : HTML5::Node) : Bool
      @f.call(n)
    end
  end

  private record SelectorSequence, matchers : Array(Matcher) do
    include Matcher
    include Select
    getter matchers : Array(Matcher)

    def initialize(@matchers = Array(Matcher).new)
    end

    # Single-pass recursive DFS: check node, then recurse into children.
    # Uses a Set for O(1) deduplication within this tree walk.
    def select(n : HTML5::Node, selected = [] of HTML5::Node) : Array(HTML5::Node)
      seen = Set(UInt64).new
      select_recursive(n, selected, seen)
      selected
    end

    private def select_recursive(n : HTML5::Node, selected : Array(HTML5::Node), seen : Set(UInt64))
      if matches(n) && !seen.includes?(n.object_id)
        selected << n
        seen << n.object_id
      end
      c = n.first_child
      while c
        select_recursive(c, selected, seen)
        c = c.next_sibling
      end
    end

    def select1(n : HTML5::Node) : Array(HTML5::Node)
      return [n] if matches(n)
      selected = [] of HTML5::Node
      c = n.first_child
      while (c)
        selected += self.select(c)
        c = c.next_sibling
      end
      selected
    end

    def matches(n : HTML5::Node) : Bool
      @matchers.each do |m|
        return false unless m.matches(n)
      end
      true
    end
  end

  private class CombinatorSelector
    include Select

    def initialize(@combinator : TokenType, @sel_seq : SelectorSequence)
    end

    def select(n : HTML5::Node, selected = [] of HTML5::Node) : Array(HTML5::Node)
      case @combinator
      when .greater?
        child = n.first_child
        while (child)
          selected << child if @sel_seq.matches(child) && !child.parent.nil?
          child = child.next_sibling
        end
      when .tilde?
        sibl = n.next_sibling
        while (sibl)
          # Use object_id check instead of linear scan for dedup
          selected << sibl if @sel_seq.matches(sibl) && !selected.any? { |s| s.same?(sibl) }
          sibl = sibl.next_sibling
        end
      when .plus?
        sibl = n.next_sibling
        while (sibl)
          selected << sibl if @sel_seq.matches(sibl)
          # check matches against only the first element
          break if sibl.element?
          sibl = sibl.next_sibling
        end
      when .not?
        selected << n if !@sel_seq.matches(n)
      else
        # Descendant combinator: use Set for O(1) dedup within this walk
        seen = Set(UInt64).new
        child = n.first_child
        while (child)
          select_descendants(child, selected, seen)
          child = child.next_sibling
        end
      end
      selected
    end

    # Recursive descendant selection with O(1) dedup via Set
    private def select_descendants(n : HTML5::Node, selected : Array(HTML5::Node), seen : Set(UInt64))
      if @sel_seq.matches(n) && !seen.includes?(n.object_id)
        selected << n
        seen << n.object_id
      end
      child = n.first_child
      while child
        select_descendants(child, selected, seen)
        child = child.next_sibling
      end
    end
  end

  private class Universal
    include Matcher

    def matches(n : HTML5::Node) : Bool
      n.element?
    end
  end

  private class TypeSelector
    include Matcher

    def initialize(@ele : String)
    end

    def matches(n : HTML5::Node) : Bool
      n.element? && n.data == @ele
    end
  end

  private class AttrSelector
    include Matcher

    def initialize(@key : String)
    end

    def matches(n : HTML5::Node) : Bool
      n.attr.each do |a|
        return true if a.key == @key
      end
      false
    end
  end

  private class AttrMatcher
    include Matcher
    @values : Array(String)

    def initialize(@key : String, @val : String)
      @values = @val.split(' ').reject(&.blank?)
    end

    def matches(n : HTML5::Node) : Bool
      n.attr.each do |a|
        if a.key == @key
          return false if @values.empty?
          # Fast path for single value match (common case: class="foo" or id="bar")
          if @values.size == 1
            target = @values[0]
            # Check if the attribute value is exactly the target (no spaces)
            return a.val == target unless a.val.includes?(' ')
            # Otherwise scan space-separated tokens without allocating an array
            return CSS.scan_space_separated(a.val, target)
          end
          # Multi-value match: all values must be present
          attr_vals = a.val.split(' ').reject(&.blank?)
          return false if attr_vals.empty?
          @values.each do |v|
            return false unless attr_vals.includes?(v)
          end
          return true
        end
      end
      false
    end
  end

  private class AttrCompMatcher
    include Matcher

    def initialize(@key : String, @val : String, @comp : Proc(String, String, Bool))
    end

    def matches(n : HTML5::Node) : Bool
      n.attr.each do |a|
        if a.key == @key
          return @comp.call(a.val, @val)
        end
      end
      false
    end
  end

  private class Negation
    include Matcher

    def initialize(@m : Matcher)
    end

    def matches(n : HTML5::Node) : Bool
      !@m.matches(n)
    end
  end

  private class NthChildPseudo
    include Matcher

    def initialize(@a : Int32, @b : Int32, @last = false, @oftype = false)
    end

    def matches(n : HTML5::Node) : Bool
      if @a == 0
        if @last
          last_child_match(n)
        else
          nth_child_match(n)
        end
      else
        child_match(n)
      end
    end

    def nth_child_match(n : HTML5::Node) : Bool
      return false unless n.element?
      parent = n.parent
      return false if parent.nil?
      return false if parent.document?
      count = 0
      c = parent.first_child
      while (c)
        if !c.element? || (@oftype && c.data != n.data)
          c = c.next_sibling
          next
        end
        count += 1
        return (count == @b) if c == n
        return false if count >= @b
        c = c.next_sibling
      end
      false
    end

    def last_child_match(n : HTML5::Node) : Bool
      return false unless n.element?
      parent = n.parent
      return false if parent.nil?
      return false if parent.document?
      count = 0
      c = parent.last_child
      while (c)
        if !c.element? || (@oftype && c.data != n.data)
          c = c.prev_sibling
          next
        end
        count += 1
        return (count == @b) if c == n
        return false if count >= @b
        c = c.prev_sibling
      end
      false
    end

    def child_match(n : HTML5::Node) : Bool
      return false unless n.element?
      parent = n.parent
      return false if parent.nil?
      return false if parent.document?
      i = -1
      count = 0
      c = parent.first_child
      while (c)
        if !c.element? || (@oftype && c.data != n.data)
          c = c.next_sibling
          next
        end
        count += 1
        if c == n
          i = count
          break unless @last
        end
        c = c.next_sibling
      end

      # This shouldn't happen, since n should always be one of its parent's children
      return false if i == -1
      i = count - i + 1 if @last
      i -= @b
      return i == 0 if @a == 0
      (i % @a == 0) && (i // @a >= 0)
    end
  end

  private class OnlyChildPseudo
    include Matcher

    def initialize(@oftype = false)
    end

    def matches(n : HTML5::Node) : Bool
      return false unless n.element?
      parent = n.parent
      return false if parent.nil?
      return false if parent.document?
      count = 0
      c = parent.first_child
      while (c)
        if !c.element? || (@oftype && c.data != n.data)
          c = c.next_sibling
          next
        end
        count += 1
        return false if count > 1
        c = c.next_sibling
      end
      count == 1
    end
  end

  # Scan space-separated tokens in a string without allocating.
  # Returns true if `want` is found as a space-separated token in `got`.
  protected def self.scan_space_separated(got : String, want : String) : Bool
    pos = 0
    while pos < got.size
      while pos < got.size && got[pos] == ' '
        pos += 1
      end
      break if pos >= got.size
      token_start = pos
      while pos < got.size && got[pos] != ' '
        pos += 1
      end
      return true if got[token_start...pos] == want
    end
    false
  end

  # Non-allocating includes matcher: checks if `want` is a space-separated token in `got`
  protected def self.includes_matcher(got : String, want : String)
    scan_space_separated(got, want)
  end

  # Non-allocating dash matcher: checks if any space-separated token in `got`
  # equals `want` or starts with `want` followed by '-'
  protected def self.dash_matcher(got : String, want : String)
    pos = 0
    while pos < got.size
      while pos < got.size && got[pos] == ' '
        pos += 1
      end
      break if pos >= got.size
      token_start = pos
      while pos < got.size && got[pos] != ' '
        pos += 1
      end
      token = got[token_start...pos]
      next if token.empty?
      return true if token == want || (token.size > want.size && token.starts_with?(want) && token[want.size] == '-')
    end
    false
  end

  protected def self.empty(n : HTML5::Node) : Bool
    return false unless n.element?
    c = n.first_child
    while (c)
      return false if c.element? || c.text?
      c = c.next_sibling
    end
    true
  end

  protected def self.root(n : HTML5::Node) : Bool
    return false unless n.element?
    parent = n.parent
    return false if parent.nil?
    parent.document?
  end

  protected def self.input(n : HTML5::Node) : Bool
    n.element? && {"input", "select", "textarea", "button"}.includes?(n.data)
  end

  private class ScopeMatcher
    include Matcher

    def initialize(@scope_node : HTML5::Node)
    end

    def matches(n : HTML5::Node) : Bool
      n == @scope_node
    end
  end
end
