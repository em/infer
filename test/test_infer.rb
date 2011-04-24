#!/usr/bin/env ruby

require 'test/unit'
require_relative '../infer'

class TestInfer < Test::Unit::TestCase
  def setup
  end

  def test_directory_vs_file_rank
    i = Infer.new("./pets cat")
    i.run
  end
end
