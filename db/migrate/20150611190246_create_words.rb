class CreateWords < ActiveRecord::Migration
  def change
    create_table :words do |t|
      t.string :native
      t.string :transcription
      t.string :translation

      t.timestamps null: false
    end
  end
end
