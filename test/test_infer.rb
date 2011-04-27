#!/usr/bin/env ruby

require 'test/unit'
require_relative '../infer'

class TestInfer < Test::Unit::TestCase
  def setup
  end

  def test_basic_path_ranking
    i = Infer.new('test')
    assert_equal i.rank_file('this/is/a/test')[1], "test".length.to_f/"this/is/a/test".length
  end

  def test_directory_vs_file_rank
    i = Infer.new("./pets cat")
    i.run
  end
end
