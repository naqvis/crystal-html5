require "./spec_helper"
require "dir"
require "colorize"

module HTML5
  TEST_DATA_ROOT = "#{__DIR__}/testdata/"
  TEST_DATA_DIRS = ["#{TEST_DATA_ROOT}webkit/", "#{TEST_DATA_ROOT}more/"]
  it "Test Parser with all available test suites" do
    sep = "*" * 10
    TEST_DATA_DIRS.each do |dir|
      Dir.glob(dir + "*.dat") do |file|
        puts "\n\t\t#{sep}  Running Test Suite - #{File.basename(file)} #{sep}\n".colorize.green
        File.open(file) do |f|
          while (ta = read_parse_test(f))
            puts "Running Test case: ".colorize(:light_blue)
            pp ta.text
            test_parse_case(ta.text, ta.want, ta.context, **{scripting: ta.scripting})
          end
        end
      end
    end
  end

  it "Test Parser without scripting enabled" do
    text = %(<noscript><img src='https://golang.org/doc/gopher/frontpage.png' /></noscript><p><img src='https://golang.org/doc/gopher/doc.png' /></p>)
    want = <<-EOF
| <html>
|   <head>
|     <noscript>
|   <body>
|     <img>
|       src="https://golang.org/doc/gopher/frontpage.png"
|     <p>
|       <img>
|         src="https://golang.org/doc/gopher/doc.png"

EOF

    test_parse_case(text, want, "", **{scripting: false})
  end

  it "Test Node consistency" do
    # err_node is a Node whose data_atom and data do not match
    err_node = Node.new(
      type: NodeType::Element,
      data_atom: Atom::Frameset,
      data: "table"
    )
    expect_raises(HTMLException, "inconsistent Node: data_atom=frameset, data=table") do
      parse_fragment(IO::Memory.new("<p>should not work</p>"), err_node)
    end
  end

  it "Test parse_fragment with nil context" do
    parse_fragment(IO::Memory.new("<p>should not raise any exception"), nil)
  end
end
