# typed: ignore

RSpec.describe "Changeset Merge Events", with_sorbet: false do
  let(:log) { [] }
  let(:event_catalog_klass) do
    log = self.log
    Class.new do
      define_method(:dispatch) { |event| log << [event.name, event.payload] }
      define_method(:known_event?) { |name| %i[parent_event child_event].include?(name) }
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

  it "dispatches the child's events once, after the commit, with the parent's" do
    rows = []
    parent
      .add_db_operation(-> { rows << :parent_row })
      .add_event(:parent_event, {id: 1})
      .add_db_operation(-> {
        child = build_child(rows)
        child.commit_db_operations
        parent.merge_events(child)
      })

    parent.push!

    expect(log).to eq([
      :transaction_start,
      :transaction_start,
      [:child_write, [:parent_row]],
      :transaction_end,
      :transaction_end,
      [:parent_event, {id: 1}],
      [:child_event, {rows: [:parent_row]}]
    ])
  end

  it "dedupes the child's events against the parent's" do
    child = Changeset.new(event_catalog_klass.new)
      .add_event(:parent_event, {id: 1})
      .add_event(:child_event, {id: 2})
    parent.add_event(:parent_event, {id: 1})

    parent.merge_events(child)
    parent.push!

    expect(log).to eq([
      :transaction_start,
      :transaction_end,
      [:parent_event, {id: 1}],
      [:child_event, {id: 2}]
    ])
  end

  it "does not run the child's db operations" do
    db_operation = spy("db_operation")
    child = Changeset.new(event_catalog_klass.new).add_db_operation(db_operation)

    parent.merge_events(child)
    parent.push!

    expect(db_operation).not_to have_received(:call)
  end

  it "dispatches nothing when the commit raises" do
    parent
      .add_event(:parent_event, {id: 1})
      .add_db_operation(-> { parent.merge_events(build_child([])) })
      .add_db_operation(-> { raise "boom" })

    expect { parent.push! }.to raise_error("boom")
    expect(log).to eq([:transaction_start])
  end

  it "prevents pushing the child afterwards" do
    child = build_child([])

    parent.merge_events(child)

    expect(child).to be_merged
    expect { child.push! }.to raise_error(
      Changeset::Errors::AlreadyMergedError,
      "cannot push a changeset that has been merged into a parent"
    )
  end

  it "refuses a child that has already been pushed" do
    child = build_child([])
    child.push!

    expect { parent.merge_events(child) }.to raise_error(
      Changeset::Errors::AlreadyPushedError,
      "cannot take the events of a pushed changeset"
    )
  end

  it "refuses a child that has already been merged" do
    child = build_child([])
    Changeset.new.merge_events(child)

    expect { parent.merge_events(child) }.to raise_error(
      Changeset::Errors::AlreadyMergedError,
      "cannot take the events of a merged changeset"
    )
  end
end
