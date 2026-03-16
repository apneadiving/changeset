# typed: ignore

RSpec.describe "Changeset Guards", with_sorbet: false do
  before do
    Changeset.configure do |config|
      config.db_transaction_wrapper = ->(&block) { block.call }
      config.already_in_transaction = nil
    end
  end

  describe "double push protection" do
    it "raises AlreadyPushedError on second push!" do
      changeset = Changeset.new
      changeset.push!

      expect { changeset.push! }.to raise_error(
        Changeset::Errors::AlreadyPushedError,
        "this changeset has already been pushed"
      )
    end

    it "raises even if the changeset is empty" do
      changeset = Changeset.new
      changeset.push!

      expect { changeset.push! }.to raise_error(Changeset::Errors::AlreadyPushedError)
    end

    it "does not prevent pushing different changesets" do
      Changeset.new.push!

      expect { Changeset.new.push! }.not_to raise_error
    end
  end

  describe "merge guards" do
    it "prevents pushing a child that has been merged" do
      parent = Changeset.new
      child = Changeset.new

      parent.merge_child(child)

      expect { child.push! }.to raise_error(
        Changeset::Errors::AlreadyMergedError,
        "cannot push a changeset that has been merged into a parent"
      )
    end

    it "prevents merging a child that has already been pushed" do
      parent = Changeset.new
      child = Changeset.new
      child.push!

      expect { parent.merge_child(child) }.to raise_error(
        Changeset::Errors::AlreadyPushedError,
        "cannot merge a changeset that has already been pushed"
      )
    end

    it "prevents merging a child that has already been merged" do
      parent1 = Changeset.new
      parent2 = Changeset.new
      child = Changeset.new

      parent1.merge_child(child)

      expect { parent2.merge_child(child) }.to raise_error(
        Changeset::Errors::AlreadyMergedError,
        "cannot merge a changeset that has already been merged"
      )
    end

    it "allows pushing the parent after merging a child" do
      parent = Changeset.new
      child = Changeset.new

      parent.merge_child(child)

      expect { parent.push! }.not_to raise_error
    end
  end

  describe "already in transaction detection" do
    it "raises AlreadyInTransactionError when checker returns true" do
      Changeset.configure do |config|
        config.db_transaction_wrapper = ->(&block) { block.call }
        config.already_in_transaction = -> { true }
      end

      changeset = Changeset.new

      expect { changeset.push! }.to raise_error(
        Changeset::Errors::AlreadyInTransactionError,
        "push! called inside an open transaction"
      )
    end

    it "does not raise when checker returns false" do
      Changeset.configure do |config|
        config.db_transaction_wrapper = ->(&block) { block.call }
        config.already_in_transaction = -> { false }
      end

      changeset = Changeset.new

      expect { changeset.push! }.not_to raise_error
    end

    it "does not raise when checker is not configured" do
      changeset = Changeset.new

      expect { changeset.push! }.not_to raise_error
    end
  end
end
