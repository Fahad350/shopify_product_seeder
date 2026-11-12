class CreateSeedRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :seed_runs do |t|
      t.string :status, null: false, default: "running"
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.jsonb :results, null: false, default: []
      t.text :error_message
      t.datetime :finished_at

      t.timestamps
    end
  end
end
