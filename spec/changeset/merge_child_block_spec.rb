# typed: ignore

RSpec.describe "Changeset Merge Child with a block", with_sorbet: false do
  let(:log) { [] }
  let(:event_catalog_klass) do
    log = self.log
    Class.new do
      define_method(:dispatch) { |event| log << [event.name, event.payload] }
      define_method(:known_event?) { |name| %i[parent_event child_event grandchild_event].include?(name) }
    end
  end
  let(:parent) { Changeset.new(event_catalog_klass.new) }

  before do
    log = self.log
    Changeset.configure do |config|
      config.db_transaction_wrapper = ->(&block) {
        log << :transaction_start
        block.call
        log << :transaction_end
      }
      config.already_in_transaction = nil
    end
  end

  # a child that can only be built after the parent's earlier db operations
  def build_child(rows)
    Changeset.new(event_catalog_klass.new)
      .add_db_operation(-> { log << [:child_write, rows.dup] })
      .add_event(:child_event, {rows: rows.dup})
  end

  it "builds the child at its position, runs its db operations there and dispatches its events after the commit" do
    rows = []
    parent
      .add_db_operation(-> { rows << :parent_row })
      .add_event(:parent_event, {id: 1})
      .merge_child { build_child(rows) }
      .add_db_operation(-> { log << [:parent_write_after_child, rows.dup] })

    parent.push!

    expect(log).to eq([
      :transaction_start,
      :transaction_start,
      [:child_write, [:parent_row]],
      :transaction_end,
      [:parent_write_after_child, [:parent_row]],
      :transaction_end,
      [:parent_event, {id: 1}],
      [:child_event, {rows: [:parent_row]}]
    ])
  end

  it "does not build the child before the commit" do
    built = false
    parent.merge_child do
      built = true
      Changeset.new
    end

    expect(built).to be false
    parent.push!
    expect(built).to be true
  end

  it "nests: a child can merge a grandchild with a block" do
    parent.merge_child do
      Changeset.new(event_catalog_klass.new)
        .add_db_operation(-> { log << :child_write })
        .merge_child do
          Changeset.new(event_catalog_klass.new)
            .add_db_operation(-> { log << :grandchild_write })
            .add_event(:grandchild_event, {})
        end
        .add_db_operation(-> { log << :child_write_after_grandchild })
        .add_event(:child_event, {})
    end

    parent.push!

    expect(log).to eq([
      :transaction_start,
      :transaction_start,
      :child_write,
      :transaction_start,
      :grandchild_write,
      :transaction_end,
      :child_write_after_grandchild,
      :transaction_end,
      :transaction_end,
      [:child_event, {}],
      [:grandchild_event, {}]
    ])
  end

  it "dispatches the block child's events when the changeset holding the block was merged eagerly into a parent" do
    rows = []
    child = Changeset.new(event_catalog_klass.new)
      .add_db_operation(-> { rows << :child_row })
      .merge_child { build_child(rows) }
      .add_event(:child_event, {id: :static})
    parent.add_event(:parent_event, {id: 1}).merge_child(child)

    parent.push!

    expect(log).to eq([
      :transaction_start,
      :transaction_start,
      [:child_write, [:child_row]],
      :transaction_end,
      :transaction_end,
      [:parent_event, {id: 1}],
      [:child_event, {id: :static}],
      [:child_event, {rows: [:child_row]}]
    ])
  end

  it "dispatches them through several eager merges, and marks the block child as merged" do
    grandchild = build_child([])
    child = Changeset.new(event_catalog_klass.new).merge_child { grandchild }
    middle = Changeset.new(event_catalog_klass.new).merge_child(child)
    parent.merge_child(middle)

    parent.push!

    expect(log.last).to eq([:child_event, {rows: []}])
    expect(grandchild).to be_merged
    expect { grandchild.push! }.to raise_error(Changeset::Errors::AlreadyMergedError)
  end

  it "dedupes the child's events against the parent's" do
    parent
      .add_event(:parent_event, {id: 1})
      .merge_child do
        Changeset.new(event_catalog_klass.new)
          .add_event(:parent_event, {id: 1})
          .add_event(:child_event, {id: 2})
      end

    parent.push!

    expect(log).to eq([
      :transaction_start,
      :transaction_start,
      :transaction_end,
      :transaction_end,
      [:parent_event, {id: 1}],
      [:child_event, {id: 2}]
    ])
  end

  it "dispatches nothing when a later operation raises" do
    parent
      .add_event(:parent_event, {id: 1})
      .merge_child { build_child([]) }
      .add_db_operation(-> { raise "boom" })

    expect { parent.push! }.to raise_error("boom")
    expect(log).to eq([:transaction_start, :transaction_start, [:child_write, []], :transaction_end])
  end

  it "dispatches nothing when the child's own operation raises" do
    parent
      .add_event(:parent_event, {id: 1})
      .merge_child { Changeset.new.add_db_operation(-> { raise "boom" }) }

    expect { parent.push! }.to raise_error("boom")
    expect(log).to eq([:transaction_start, :transaction_start])
  end

  it "marks the child as merged, so it cannot be pushed afterwards" do
    child = build_child([])
    parent.merge_child { child }

    parent.push!

    expect(child).to be_merged
    expect { child.push! }.to raise_error(Changeset::Errors::AlreadyMergedError)
  end

  it "refuses a block that returns something else than a changeset" do
    parent.merge_child { :not_a_changeset }

    expect { parent.push! }.to raise_error(
      Changeset::Errors::NotAChangesetError,
      "merge_child's block must return a Changeset, got Symbol"
    )
  end

  def merge_with_a_return(changeset)
    changeset.merge_child { return Changeset.new }
  end

  it "refuses a block that uses return, before writing anything" do
    merge_with_a_return(parent)

    expect { parent.push! }.to raise_error(ArgumentError, "merge_child's block must not return: end it with the child changeset")
    expect(log).to eq([:transaction_start])
  end

  it "refuses a block that returns an already pushed changeset" do
    child = build_child([])
    child.push!
    parent.merge_child { child }

    expect { parent.push! }.to raise_error(
      Changeset::Errors::AlreadyPushedError,
      "cannot merge a changeset that has already been pushed"
    )
  end

  it "refuses a block that returns an already merged changeset" do
    child = build_child([])
    Changeset.new.merge_child(child)
    parent.merge_child { child }

    expect { parent.push! }.to raise_error(
      Changeset::Errors::AlreadyMergedError,
      "cannot merge a changeset that has already been merged"
    )
  end

  it "refuses a changeset and a block together" do
    expect { parent.merge_child(Changeset.new) { Changeset.new } }.to raise_error(
      ArgumentError,
      "merge_child takes a changeset or a block, not both"
    )
  end

  it "refuses a call with neither" do
    expect { parent.merge_child }.to raise_error(ArgumentError, "merge_child takes a changeset or a block")
  end

  it "refuses an eager merge_child while committing" do
    parent.add_db_operation(-> { parent.merge_child(build_child([])) })

    expect { parent.push! }.to raise_error(
      Changeset::Errors::CommittingError,
      "cannot call merge_child from inside a db operation: call it while building the changeset"
    )
    expect(log).to eq([:transaction_start])
  end

  it "refuses a merge_child with a block while committing, for the same reason" do
    parent.add_db_operation(-> { parent.merge_child { build_child([]) } })

    expect { parent.push! }.to raise_error(Changeset::Errors::CommittingError)
    expect(log).to eq([:transaction_start])
  end

  it "accepts an eager merge_child again once the commit is over" do
    parent.add_db_operation(-> { log << :write })
    parent.commit_db_operations

    expect { parent.merge_child(build_child([])) }.not_to raise_error
  end
end
