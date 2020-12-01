require "../node"

module HTML5
  class Node
    # Searches this node for CSS Selector *expression*. Returns all of the matched `HTML5::Node`
    def css(expression : String) : Array(Node)
      comp = CSS.compile(expression)
      comp.select(self)
    end
  end
end

module CSS
  class Selector
    def initialize(@selector_group = Array(SelectorImpl).new)
    end

    def select(n : HTML5::Node) : Array(HTML5::Node)
      matched = [] of HTML5::Node
      @selector_group.each do |sel|
        matched += sel.select(n)
      end
      matched
    end
  end

  private class SelectorImpl
    getter combs : Array(CombinatorSelector)

    def initialize(@sel_seq : SelectorSequence, @combs = Array(CombinatorSelector).new)
    end

    def select(n : HTML5::Node) : Array(HTML5::Node)
      matched = @sel_seq.select(n)
      @combs.each do |comb|
        comb_matched = [] of HTML5::Node
        matched.each do |m|
          comb_matched += comb.select(m)
        end
        matched = comb_matched
      end
      matched
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

    def initialize(@matchers = Array(Matcher).new)
    end

    def select(n : HTML5::Node) : Array(HTML5::Node)
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
    def initialize(@combinator : TokenType, @sel_seq : SelectorSequence)
    end

    def select(n : HTML5::Node) : Array(HTML5::Node)
      matched = [] of HTML5::Node
      case @combinator
      when .greater?
        child = n.first_child
        while (child)
          matched << child if @sel_seq.matches(child)
          child = child.next_sibling
        end
      when .tilde?
        sibl = n.next_sibling
        while (sibl)
          matched << sibl if @sel_seq.matches(sibl)
          sibl = sibl.next_sibling
        end
      when .plus?
        sibl = n.next_sibling
        while (sibl)
          matched << sibl if @sel_seq.matches(sibl)
          # check matches against only the first element
          break if sibl.type == HTML5::NodeType::Element
          sibl = sibl.next_sibling
        end
      else
        child = n.first_child
        while (child)
          matched += @sel_seq.select(child)
          child = child.next_sibling
        end
      end
      matched
    end
  end

  private class Universal
    include Matcher

    def matches(n : HTML5::Node) : Bool
      true
    end
  end

  private class TypeSelector
    include Matcher

    def initialize(@ele : String)
    end

    def matches(n : HTML5::Node) : Bool
      n.type == HTML5::NodeType::Element && n.data == @ele
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

    def initialize(@key : String, @val : String)
    end

    def matches(n : HTML5::Node) : Bool
      n.attr.each do |a|
        if a.key == @key
          return a.val == @val
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

  protected def self.includes_matcher(got : String, want : String)
    got.split(' ').each do |s|
      next if s.empty?
      return true if s == want
    end
    false
  end

  protected def self.dash_matcher(got : String, want : String)
    got.split('-').each do |s|
      next if s.empty?
      return true if s == want
    end
    false
  end

  protected def self.empty(n : HTML5::Node) : Bool
    c = n.first_child
    while (c)
      return false unless c.comment?
      c = c.next_sibling
    end
    true
  end

  protected def self.first_child(n : HTML5::Node) : Bool
    return false unless n.element?
    s = n.prev_sibling
    while (s)
      return false if s.element?
      s = s.prev_sibling
    end
    true
  end

  protected def self.first_of_type(n : HTML5::Node) : Bool
    return false unless n.element?
    s = n.prev_sibling
    while (s)
      return false if s.element? && s.data == n.data
      s = s.prev_sibling
    end
    true
  end

  protected def self.last_child(n : HTML5::Node) : Bool
    return false unless n.element?
    s = n.next_sibling
    while (s)
      return false if s.element?
      s = s.next_sibling
    end
    true
  end

  protected def self.last_of_type(n : HTML5::Node) : Bool
    return false unless n.element?
    s = n.next_sibling
    while (s)
      return false if s.element? && s.data == n.data
      s = s.next_sibling
    end
    true
  end

  protected def self.only_child(n : HTML5::Node) : Bool
    first_child(n) && last_child(n)
  end

  protected def self.only_of_type(n : HTML5::Node) : Bool
    first_of_type(n) && last_of_type(n)
  end

  protected def self.root(n : HTML5::Node) : Bool
    n.parent.nil?
  end

  private class NthChild
    include Matcher

    def initialize(@a : Int32, @b : Int32)
    end

    def matches(n : HTML5::Node) : Bool
      pos = 0
      s = n.prev_sibling
      while (s)
        pos += 1 if s.element?
        s = s.prev_sibling
      end

      CSS.post_matches(@a, @b, pos)
    end
  end

  protected def self.post_matches(a, b, pos)
    n = (pos - b + 1)
    (a == 0 && n == 0) || (n % a == 0 && n//a >= 0)
  end
end
