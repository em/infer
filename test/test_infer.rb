#!/usr/bin/env ruby

require 'test/unit'
require_relative '../infer'

def capture_stdout(&block)
  original_stdout = $stdout
  $stdout = StringIO.new
  begin
    yield
  ensure
    $stdout = original_stdout
  end
end

class TestInfer < Test::Unit::TestCase
  def test_basic_path_ranking
    i = Infer.new('test')
    assert_equal i.rank_file('this/is/a/test').rank, 'test'.length.to_f/'this/is/a/test'.length
  end

  def test_directory_vs_file_rank
    i = Infer.new('~/cats -p')
    capture_stdout { i.run }
    assert_equal i.results[0].path, 'cats/cats'
  end
end
