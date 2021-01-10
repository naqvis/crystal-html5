# Module `CSS` implements **W3** [Selectors Level 3](http://www.w3.org/TR/css3-selectors/) specification.
# This module is used internally by `HTML5` to provide css selector support via `HTML5::Node#css` method.
module CSS
  class CSSException < Exception
  end

  class SyntaxError < CSSException
  end
end

require "./*"
