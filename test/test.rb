require '../infer'

describe StringCaser do
it "should upcase a string" do
  caser = StringCaser.new("A String")
  caser.upcase.should == "A STRING"
end
end
