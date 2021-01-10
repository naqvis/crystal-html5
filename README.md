# Crystal-HTML5
![CI](https://github.com/naqvis/crystal-html5/workflows/CI/badge.svg)
[![GitHub release](https://img.shields.io/github/release/naqvis/crystal-html5.svg)](https://github.com/naqvis/crystal-html5/releases)
[![Docs](https://img.shields.io/badge/docs-available-brightgreen.svg)](https://naqvis.github.io/crystal-html5/)

Crystal-HTML5 shard is a **Pure Crystal** implementation of an **HTML5-compliant** `Tokenizer` and `Parser`.
The relevant specifications include:
- [https://html.spec.whatwg.org/multipage/syntax.html](https://html.spec.whatwg.org/multipage/syntax.html)
- [https://html.spec.whatwg.org/multipage/syntax.html#tokenization](https://html.spec.whatwg.org/multipage/syntax.html#tokenization)

Shard also provides **CSS Selector support** by implementing **W3** [Selectors Level 3](http://www.w3.org/TR/css3-selectors/) specification

Tokenization is done by creating a `Tokenizer` for an `IO`. It is the caller
responsibility to ensure that provided IO provides UTF-8 encoded HTML.
The tokenization algorithm implemented by this shard is not a line-by-line
transliteration of the relatively verbose state-machine in the **WHATWG**
specification. A more direct approach is used instead, where the program
counter implies the state, such as whether it is tokenizing a tag or a text
node. Specification compliance is verified by checking expected and actual
outputs over a test suite rather than aiming for algorithmic fidelity.

Parsing is done by calling `HTML5.parse` with either a String containing HTML
or an IO instance. `HTML5.parse` returns a document root as `HTML5::Node` instance.

Parsing a fragment is done by calling `HTML5.parse_fragment` with either a String containing fragment of HTML5
or an IO instance. If the fragment is the InnerHTML for an existing element, pass that element in context.
`HTML5.parse_fragment` returns a list of `HTML5::Node` that were found.



## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     html5:
       github: naqvis/crystal-html5
   ```

2. Run `shards install`

## Usage

### Example 1: Process each anchor `<a>` node.
```crystal
require "html5"

html = <<-HTML5
<!DOCTYPE html><html lang="en-US">
<head>
<title>Hello,World!</title>
</head>
<body>
<div class="container">
<header>
	<!-- Logo -->
   <h1>City Gallery</h1>
</header>
<nav>
  <ul>
    <li><a href="/London">London</a></li>
    <li><a href="/Paris">Paris</a></li>
    <li><a href="/Tokyo">Tokyo</a></li>
  </ul>
</nav>
<article>
  <h1>London</h1>
  <img src="pic_mountain.jpg" alt="Mountain View" style="width:304px;height:228px;">
  <p>London is the capital city of England. It is the most populous city in the  United Kingdom, with a metropolitan area of over 13 million inhabitants.</p>
  <p>Standing on the River Thames, London has been a major settlement for two millennia, its history going back to its founding by the Romans, who named it Londinium.</p>
</article>
<footer>Copyright &copy; W3Schools.com</footer>
</div>
</body>
</html>
HTML5

def process(node)
  if node.element? && node.data == "a"
    # Do something with node
    href = node["href"]?
    puts "#{node.first_child.try &.data} =>  #{href.try &.val}"

    # print all attributes
    node.attr.each do |a|
      # puts "#{a.key} = \"#{a.val}\""
    end
  end
  c = node.first_child
  while c
    process(c)
    c = c.next_sibling
  end
end

doc = HTML5.parse(html)
process(doc)

# Output
# London =>  /London
# Paris =>  /Paris
# Tokyo =>  /Tokyo
```

### Example 2: Parse an HTML or Fragment of HTML
```crystal
require "html5"

def parse_html(html, context)
  if context.empty?
    doc = HTML5.parse(html)
  else
    namespace = ""
    if (i = context.index(' ')) && (i >= 0)
      namespace, context = context[...i], context[i + 1..]
    end
    cnode = HTML5::Node.new(
      type: HTML5::NodeType::Element,
      data_atom: HTML5::Atom.lookup(context.to_slice),
      data: context,
      namespace: namespace,
    )

    nodes = HTML5.parse_fragment(html, cnode)
    doc = HTML5::Node.new(type: HTML5::NodeType::Document)
    nodes.each do |n|
      doc.append_child(n)
    end
  end
  doc
end

html = %(<p>Links:</p><ul><li><a href="foo">Foo</a><li><a href="/bar/baz">BarBaz</a></ul>)
doc = parse_html(html, "body")
process(doc)

# Output
# Foo =>  foo
# BarBaz =>  /bar/baz
```

### Example 3: Render `HTML5::Node` to HTML
```crystal
require "html5"

html = %(<p>Links:</p><ul><li><a href="foo">Foo</a><li><a href="/bar/baz">BarBaz</a></ul>)
doc = HTML5.parse(html)
doc.render(STDOUT)

# Output
# <html><head></head><body><p>Links:</p><ul><li><a href="foo">Foo</a></li><li><a href="/bar/baz">BarBaz</a></li></ul></body></html>
```

### Example 3: XPath Query
```crystal
require "html5"

html = %(<p>Links:</p><ul><li><a href="foo">Foo</a><li><a href="/bar/baz">BarBaz</a></ul>)
doc = HTML5.parse(html)

# Find all A elements
list = html.xpath_nodes("//a")

# Find all A elements that have `href` attribute.
list = html.xpath_nodes("//a[@href]")

# Find all A elements with `href` attribute and only return `href` value.
list = html.xpath_nodes("//a/@href")
list.each {|a| pp a.inner_text}

# Find the second `a` element
a = html.xpath("//a[2]")

# Count the number of all a elements.
v = html.xpath_float("//a")
```

Refer to specs for more sample usages. And refer to [Crystal XPath2 Shard](https://github.com/naqvis/crystal-xpath2) for details of what functions and functionality is supported by XPath implementation.

### Example 4: CSS Selector
```crystal
html = <<-HTML
  <html>
    <body>
      <table id="t1">
        <tr><td>Hello</td></tr>
      </table>
      <table id="t2">
        <tr><td>123</td><td>other</td></tr>
        <tr><td>foo</td><td>columns</td></tr>
        <tr><td>bar</td><td>are</td></tr>
        <tr><td>xyz</td><td>ignored</td></tr>
      </table>
    </body>
  </html>
HTML

node = HTML5.parse(html)
p node.css("#t2 tr td:first-child").map(&.inner_text).to_a    # => ["123", "foo", "bar", "xyz"]
p node.css("#t2 tr td:first-child").map(&.to_html(true)).to_a # => "<td>123</td>", "<td>foo</td>", "<td>bar</td>", "<td>xyz</td>"]

html = <<-HTML
<p>
  <h2 id="foo">a header</h2>
  <h2 id="bar">another header</h2>
</p>
HTML
node = HTML5.parse(html)
p node.css("h2#foo").map(&.to_html(true)).to_a # => ["<h2 id=\"foo\">a header</h2>"]

html = <<-HTML
  <div>
    <p id=p1>
    <p id=p2 class=jo>
    <p id=p3>
      <a href="some.html" id=a1>link1</a>
      <a href="some.png" id=a2>link2</a>
    <div id=bla>
      <p id=p4 class=jo>
      <p id=p5 class=bu>
      <p id=p6 class=jo>
    </div>
  </div>
HTML

node = HTML5.parse(html)
# select all p nodes which id like `*p*`
p node.css("p[id*=p]").map(&.["id"].val).to_a # => ["p1", "p2", "p3", "p4", "p5", "p6"]

# select all nodes with class "jo"
p node.css("p.jo").map(&.["id"].val).to_a # => ["p2", "p4", "p6"]
p node.css(".jo").map(&.["id"].val).to_a  # => ["p2", "p4", "p6"]

# a element with href ends like .png
p node.css(%q{a[href$=".png"]}).map(&.["id"].val).to_a # => ["a2"]

# find all a tags inside <p id=p3>, which href contain `html`
p node.css(%q{p[id=p3] > a[href*="html"]}).map(&.["id"].val).to_a # => ["a1"]
```
Refer to `spec/css` specs for more sample usages.

## Development

To run all tests:

```
crystal spec
```

## Contributing

1. Fork it (<https://github.com/naqvis/crystal-html5/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Ali Naqvi](https://github.com/naqvis) - creator and maintainer
