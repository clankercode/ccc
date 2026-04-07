# frozen_string_literal: true

module CallCodingClis
  CompletedRun = Struct.new(:argv, :exit_code, :stdout, :stderr, keyword_init: true)
end
