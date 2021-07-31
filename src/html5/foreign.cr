module HTML5
  private module ParserHelper
    extend self

    def adjust_attribute_names(aa : Array(Attribute), names : Hash(String, String))
      aa.each do |a|
        if (new_name = names[a.key]?)
          a.key = new_name
        end
      end
    end

    def adjust_foreign_attributes(aa : Array(Attribute))
      aa.each do |a|
        next if a.key.empty? || a.key[0] != 'x'

        if {"xlink:actuate", "xlink:arcrole", "xlink:href", "xlink:role", "xlink:show",
            "xlink:title", "xlink:type", "xml:base", "xml:lang", "xml:space", "xmlns:xlink"}.includes?(a.key)
          if (j = a.key.index(":"))
            a.namespace = a.key[...j]
            a.key = a.key[j + 1..]
          end
        end
      end
    end

    def html_integration_point(n : Node)
      return false unless n.type.element?

      case n.namespace
      when "math"
        if n.data == "annotation-xml"
          n.attr.each do |a|
            if a.key == "encoding"
              val = a.val.downcase
              return true if {"text/html", "application/xhtml+xml"}.includes?(val)
            end
          end
        end
      when "svg"
        return true if {"desc", "foreignObject", "title"}.includes?(n.data)
      else
        false
      end
      false
    end

    def mathml_text_integration_point(n : Node)
      return false unless n.namespace == "math"
      {"mi", "mo", "mn", "ms", "mtext"}.includes?(n.data)
    end

    # Section 12.2.6.5
    private BREAKOUT = {
      "b"          => true,
      "big"        => true,
      "blockquote" => true,
      "body"       => true,
      "br"         => true,
      "center"     => true,
      "code"       => true,
      "dd"         => true,
      "div"        => true,
      "dl"         => true,
      "dt"         => true,
      "em"         => true,
      "embed"      => true,
      "h1"         => true,
      "h2"         => true,
      "h3"         => true,
      "h4"         => true,
      "h5"         => true,
      "h6"         => true,
      "head"       => true,
      "hr"         => true,
      "i"          => true,
      "img"        => true,
      "li"         => true,
      "listing"    => true,
      "menu"       => true,
      "meta"       => true,
      "nobr"       => true,
      "ol"         => true,
      "p"          => true,
      "pre"        => true,
      "ruby"       => true,
      "s"          => true,
      "small"      => true,
      "span"       => true,
      "strong"     => true,
      "strike"     => true,
      "sub"        => true,
      "sup"        => true,
      "table"      => true,
      "tt"         => true,
      "u"          => true,
      "ul"         => true,
      "var"        => true,
    } of String => Bool

    # Section 12.2.6.5.
    private SVG_TAG_NAMED_ADJUSTMENTS = {
      "altglyph"            => "altGlyph",
      "altglyphdef"         => "altGlyphDef",
      "altglyphitem"        => "altGlyphItem",
      "animatecolor"        => "animateColor",
      "animatemotion"       => "animateMotion",
      "animatetransform"    => "animateTransform",
      "clippath"            => "clipPath",
      "feblend"             => "feBlend",
      "fecolormatrix"       => "feColorMatrix",
      "fecomponenttransfer" => "feComponentTransfer",
      "fecomposite"         => "feComposite",
      "feconvolvematrix"    => "feConvolveMatrix",
      "fediffuselighting"   => "feDiffuseLighting",
      "fedisplacementmap"   => "feDisplacementMap",
      "fedistantlight"      => "feDistantLight",
      "feflood"             => "feFlood",
      "fefunca"             => "feFuncA",
      "fefuncb"             => "feFuncB",
      "fefuncg"             => "feFuncG",
      "fefuncr"             => "feFuncR",
      "fegaussianblur"      => "feGaussianBlur",
      "feimage"             => "feImage",
      "femerge"             => "feMerge",
      "femergenode"         => "feMergeNode",
      "femorphology"        => "feMorphology",
      "feoffset"            => "feOffset",
      "fepointlight"        => "fePointLight",
      "fespecularlighting"  => "feSpecularLighting",
      "fespotlight"         => "feSpotLight",
      "fetile"              => "feTile",
      "feturbulence"        => "feTurbulence",
      "foreignobject"       => "foreignObject",
      "glyphref"            => "glyphRef",
      "lineargradient"      => "linearGradient",
      "radialgradient"      => "radialGradient",
      "textpath"            => "textPath",
    } of String => String

    # Section 12.2.6.1
    private MATHML_ATTRIBUTE_ADJUSTMENTS = {
      "definitionurl" => "definitionURL",
    } of String => String

    private SVG_ATTRIBUTE_ADJUSTMENTS = {
      "attributename"             => "attributeName",
      "attributetype"             => "attributeType",
      "basefrequency"             => "baseFrequency",
      "baseprofile"               => "baseProfile",
      "calcmode"                  => "calcMode",
      "clippathunits"             => "clipPathUnits",
      "contentscripttype"         => "contentScriptType",
      "contentstyletype"          => "contentStyleType",
      "diffuseconstant"           => "diffuseConstant",
      "edgemode"                  => "edgeMode",
      "externalresourcesrequired" => "externalResourcesRequired",
      "filterunits"               => "filterUnits",
      "glyphref"                  => "glyphRef",
      "gradienttransform"         => "gradientTransform",
      "gradientunits"             => "gradientUnits",
      "kernelmatrix"              => "kernelMatrix",
      "kernelunitlength"          => "kernelUnitLength",
      "keypoints"                 => "keyPoints",
      "keysplines"                => "keySplines",
      "keytimes"                  => "keyTimes",
      "lengthadjust"              => "lengthAdjust",
      "limitingconeangle"         => "limitingConeAngle",
      "markerheight"              => "markerHeight",
      "markerunits"               => "markerUnits",
      "markerwidth"               => "markerWidth",
      "maskcontentunits"          => "maskContentUnits",
      "maskunits"                 => "maskUnits",
      "numoctaves"                => "numOctaves",
      "pathlength"                => "pathLength",
      "patterncontentunits"       => "patternContentUnits",
      "patterntransform"          => "patternTransform",
      "patternunits"              => "patternUnits",
      "pointsatx"                 => "pointsAtX",
      "pointsaty"                 => "pointsAtY",
      "pointsatz"                 => "pointsAtZ",
      "preservealpha"             => "preserveAlpha",
      "preserveaspectratio"       => "preserveAspectRatio",
      "primitiveunits"            => "primitiveUnits",
      "refx"                      => "refX",
      "refy"                      => "refY",
      "repeatcount"               => "repeatCount",
      "repeatdur"                 => "repeatDur",
      "requiredextensions"        => "requiredExtensions",
      "requiredfeatures"          => "requiredFeatures",
      "specularconstant"          => "specularConstant",
      "specularexponent"          => "specularExponent",
      "spreadmethod"              => "spreadMethod",
      "startoffset"               => "startOffset",
      "stddeviation"              => "stdDeviation",
      "stitchtiles"               => "stitchTiles",
      "surfacescale"              => "surfaceScale",
      "systemlanguage"            => "systemLanguage",
      "tablevalues"               => "tableValues",
      "targetx"                   => "targetX",
      "targety"                   => "targetY",
      "textlength"                => "textLength",
      "viewbox"                   => "viewBox",
      "viewtarget"                => "viewTarget",
      "xchannelselector"          => "xChannelSelector",
      "ychannelselector"          => "yChannelSelector",
      "zoomandpan"                => "zoomAndPan",
    } of String => String
  end
end
