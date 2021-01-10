module HTML5
  private module ParserHelper
    # Section 12.2.4.2 of the HTML5 specification says "The following elements
    # have varying levels of special parsing rules".
    # https://html.spec.whatwg.org/multipage/syntax.html#the-stack-of-open-elements

    private SPECIAL_ELEMENT_MAP = {
      "address"    => true,
      "applet"     => true,
      "area"       => true,
      "article"    => true,
      "aside"      => true,
      "base"       => true,
      "basefont"   => true,
      "bgsound"    => true,
      "blockquote" => true,
      "body"       => true,
      "br"         => true,
      "button"     => true,
      "caption"    => true,
      "center"     => true,
      "col"        => true,
      "colgroup"   => true,
      "dd"         => true,
      "details"    => true,
      "dir"        => true,
      "div"        => true,
      "dl"         => true,
      "dt"         => true,
      "embed"      => true,
      "fieldset"   => true,
      "figcaption" => true,
      "figure"     => true,
      "footer"     => true,
      "form"       => true,
      "frame"      => true,
      "frameset"   => true,
      "h1"         => true,
      "h2"         => true,
      "h3"         => true,
      "h4"         => true,
      "h5"         => true,
      "h6"         => true,
      "head"       => true,
      "header"     => true,
      "hgroup"     => true,
      "hr"         => true,
      "html"       => true,
      "iframe"     => true,
      "img"        => true,
      "input"      => true,
      "keygen"     => true,
      "li"         => true,
      "link"       => true,
      "listing"    => true,
      "main"       => true,
      "marquee"    => true,
      "menu"       => true,
      "meta"       => true,
      "nav"        => true,
      "noembed"    => true,
      "noframes"   => true,
      "noscript"   => true,
      "object"     => true,
      "ol"         => true,
      "p"          => true,
      "param"      => true,
      "plaintext"  => true,
      "pre"        => true,
      "script"     => true,
      "section"    => true,
      "select"     => true,
      "source"     => true,
      "style"      => true,
      "summary"    => true,
      "table"      => true,
      "tbody"      => true,
      "td"         => true,
      "template"   => true,
      "textarea"   => true,
      "tfoot"      => true,
      "th"         => true,
      "thead"      => true,
      "title"      => true,
      "tr"         => true,
      "track"      => true,
      "ul"         => true,
      "wbr"        => true,
      "xmp"        => true,
    }

    protected def self.special_element?(element : Node) : Bool
      case element.namespace
      when "", "html"
        SPECIAL_ELEMENT_MAP[element.data]? || false
      when "math"
        case element.data
        when "mi", "mo", "mn", "ms", "mtext", "annotation-xml"
          true
        else
          false
        end
      when "svg"
        case element.data
        when "foreignObject", "desc", "title"
          true
        else
          false
        end
      else
        false
      end
    end
  end
end
