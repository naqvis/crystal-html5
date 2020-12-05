require "../spec_helper"

module CSS
  private def self.run_test(num, html, sel, want)
    node = HTML5.parse(html)
    selected = sel.select(node)
    fail "case=#{num}: #{html} -  want num selected=#{want.size}, got=#{selected.size}\n#{selected.map(&.to_html(true))}" unless selected.size == want.size
    i = 0
    while i < selected.size && i < want.size
      got = selected[i].to_html(true)
      fail "case=#{num} ele=#{i}: want=#{want[i]}, got=#{got}" unless want[i] == got
      i += 1
    end
  end
end
