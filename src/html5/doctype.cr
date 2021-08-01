module HTML5
  private module ParserHelper
    extend self

    # parse_doctype parses the data from a DoctypeToken into a name,
    # public identifier, and system identifier. It returns a Node whose Type
    # is DoctypeNode, whose Data is the name, and which has attributes
    # named "system" and "public" for the two identifiers if they were present.
    # quirks is whether the document should be parsed in "quirks mode".
    def parse_doctype(s : String)
      n = Node.new(type: NodeType::Doctype)

      # Find the name.
      space = HTML5.index_any(s, WHITE_SPACE)
      space = s.size if space == -1

      n.data = s[...space]
      # The comparison to "html" is case-sensitive.
      quirks = n.data != "html" ? true : false

      n.data = n.data.downcase
      s = s[space..].lstrip(WHITE_SPACE)

      if s.size < 6
        # It can't start with "PUBLIC" or "SYSTEM".
        # Ignore the rest of the string.
        return {n, quirks || !s.empty?}
      end

      key = s[...6].downcase
      s = s[6..]
      while {"public", "system"}.includes?(key)
        s = s.lstrip(WHITE_SPACE)
        break if s.empty?

        quote = s[0]
        break unless {'"', '\''}.includes?(quote)
        s = s[1..]
        q = s.index(quote) || -1
        if q == -1
          id = s
        else
          id = s[...q]
          s = s[q + 1..]
        end
        n.attr << Attribute.new(key: key, val: id)
        key = key == "public" ? "system" : ""
      end

      if !key.empty? || !s.empty?
        quirks = true
      elsif n.attr.size > 0
        if n.attr[0].key == "public"
          public = n.attr[0].val.downcase
          case public
          when "-//w3o//dtd w3 html strict 3.0//en//", "-/w3d/dtd html 4.0 transitional/en", "html"
            quirks = true
          else
            QUIRKY_IDS.each do |_q|
              if public.starts_with?(_q)
                quirks = true
                break
              end
            end
          end
          # The following two public IDs only cause quirks mode if there is no system ID
          if n.attr.size == 1 && public.starts_with?("-//w3c//dtd html 4.01 frameset//") ||
             public.starts_with?("-//w3c//dtd html 4.01 transitional//")
            quirks = true
          end
        end
        if (last_attr = n.attr[-1]) && (last_attr.key == "system") &&
           (last_attr.val.downcase == "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd")
          quirks = true
        end
      end
      {n, quirks}
    end

    # QUIRKY_IDS is a list of public doctype identifiers that cause a document
    # to be interpreted in quirks mode. The identifiers should be in lower case.
    private QUIRKY_IDS = {
      "+//silmaril//dtd html pro v0r11 19970101//",
      "-//advasoft ltd//dtd html 3.0 aswedit + extensions//",
      "-//as//dtd html 3.0 aswedit + extensions//",
      "-//ietf//dtd html 2.0 level 1//",
      "-//ietf//dtd html 2.0 level 2//",
      "-//ietf//dtd html 2.0 strict level 1//",
      "-//ietf//dtd html 2.0 strict level 2//",
      "-//ietf//dtd html 2.0 strict//",
      "-//ietf//dtd html 2.0//",
      "-//ietf//dtd html 2.1e//",
      "-//ietf//dtd html 3.0//",
      "-//ietf//dtd html 3.2 final//",
      "-//ietf//dtd html 3.2//",
      "-//ietf//dtd html 3//",
      "-//ietf//dtd html level 0//",
      "-//ietf//dtd html level 1//",
      "-//ietf//dtd html level 2//",
      "-//ietf//dtd html level 3//",
      "-//ietf//dtd html strict level 0//",
      "-//ietf//dtd html strict level 1//",
      "-//ietf//dtd html strict level 2//",
      "-//ietf//dtd html strict level 3//",
      "-//ietf//dtd html strict//",
      "-//ietf//dtd html//",
      "-//metrius//dtd metrius presentational//",
      "-//microsoft//dtd internet explorer 2.0 html strict//",
      "-//microsoft//dtd internet explorer 2.0 html//",
      "-//microsoft//dtd internet explorer 2.0 tables//",
      "-//microsoft//dtd internet explorer 3.0 html strict//",
      "-//microsoft//dtd internet explorer 3.0 html//",
      "-//microsoft//dtd internet explorer 3.0 tables//",
      "-//netscape comm. corp.//dtd html//",
      "-//netscape comm. corp.//dtd strict html//",
      "-//o'reilly and associates//dtd html 2.0//",
      "-//o'reilly and associates//dtd html extended 1.0//",
      "-//o'reilly and associates//dtd html extended relaxed 1.0//",
      "-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//",
      "-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//",
      "-//spyglass//dtd html 2.0 extended//",
      "-//sq//dtd html 2.0 hotmetal + extensions//",
      "-//sun microsystems corp.//dtd hotjava html//",
      "-//sun microsystems corp.//dtd hotjava strict html//",
      "-//w3c//dtd html 3 1995-03-24//",
      "-//w3c//dtd html 3.2 draft//",
      "-//w3c//dtd html 3.2 final//",
      "-//w3c//dtd html 3.2//",
      "-//w3c//dtd html 3.2s draft//",
      "-//w3c//dtd html 4.0 frameset//",
      "-//w3c//dtd html 4.0 transitional//",
      "-//w3c//dtd html experimental 19960712//",
      "-//w3c//dtd html experimental 970421//",
      "-//w3c//dtd w3 html//",
      "-//w3o//dtd w3 html 3.0//",
      "-//webtechs//dtd mozilla html 2.0//",
      "-//webtechs//dtd mozilla html//",
    }
  end
end
