require File.dirname(__FILE__) + '/spec_helper'

describe WpGenerate do
  it "should parse options correctly" do
    global_args = %w[-a -b --see]
    local_args = %w[-o -opt test --p -a]
    args = global_args + %w[spec_helper/generator] + local_args

    class WpGenerate::Generator::SpecHelper; class Generator; end; end
    g = WpGenerate::Generator::SpecHelper::Generator.new
    g.should_receive(:generate)
    WpGenerate::Generator::SpecHelper::Generator.should_receive(:new).with(local_args, global_args).and_return(g)

    WpGenerate.generate args
  end

  it "should raise an exception with no args" do
    lambda { WpGenerate.generate([]) }.should raise_error ArgumentError
  end

  it "should raise an exception with no generator name" do
    lambda { WpGenerate.generate(%w[-hello --there]) }.should raise_error ArgumentError
  end
end
