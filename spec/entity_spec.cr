require "./spec_helper"

module HTML5
  it "Verify that the length of UTF-8 encoding of each value is <= 1 + key.size" do
    ENTITY.each do |k, v|
      if 1 + k.size < v.bytesize
        fail "escaped entity &#{k} is shorter than its UTF-8 encoding #{v}"
      end

      if k.size > LONGEST_ENTITY_WITHOUT_SEMICOLON && k[k.size - 1] != ';'
        fail "entity name #{k} is #{k.size} characters, but LONGEST_ENTITY_WITHOUT_SEMICOLON=#{LONGEST_ENTITY_WITHOUT_SEMICOLON}"
      end
    end
    ENTITY2.each do |k, v|
      if 1 + k.size < v[0].bytesize + v[1].bytesize
        fail "escaped entity &#{k} is shorter than its UTF-8 encoding #{v[0]} #{v[1]}"
      end
    end
  end
end
