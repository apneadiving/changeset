# typed: true

class Changeset
  # What `merge_child` records when given a block. Not a db operation but a merge to perform
  # while committing, by whichever changeset commits it: the one that received the block, or the
  # parent that copied it in through an eager merge.
  class DeferredMerge
    attr_reader :build_child

    def initialize(build_child)
      @build_child = build_child
    end
  end
end
