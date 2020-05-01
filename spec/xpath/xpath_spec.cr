require "./spec_helper"

module HTML5
  it "Test XPath" do
    node = TEST_DOC.xpath("//html").not_nil!
    fail "//html[@Lang] != en-US" unless "en-US" == node.attribute_value("lang")

    node = TEST_DOC.xpath("//header").not_nil!
    fail "inner_text() have comment node text" if node.inner_text.index("Logo")
    fail "output_html() should have comment node text" unless node.to_html.index("Logo")

    link = TEST_DOC.xpath("//a[1]/@href")
    fail "link is nil" if link.nil?
    v = link.inner_text
    fail "expected value is /London, but got #{v}" unless v == "/London"

    doc = parse(%(<html><b attr="1"></b></html>))
    node = doc.xpath("//b/@attr/..")
    fail "//b/@id/.. != <b></b>" unless node.not_nil!.data == "b"

    nodes = TEST_DOC.xpath_nodes("//a")
    nodes.size.should eq(3)

    list = TEST_DOC.xpath_nodes("//a[@href]")
    list.size.should eq(3)
    expected = ["London", "Paris", "Tokyo"]
    expected.each_with_index do |e, i|
      list[i].inner_text.should eq(e)
    end

    1_f64.should eq(TEST_DOC.xpath_float("count(//img)"))
  end

  it "Test" do
    list = TEST_DOC.xpath_nodes("//a")
    list.each { |a| pp a.inner_text }
  end
end
