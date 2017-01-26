class CreateTopicToWords < ActiveRecord::Migration
  def change
    create_table :topic_to_words do |t|
      t.belongs_to :topic, index: true
      t.belongs_to :word, index: true

      t.timestamps null: false
    end
    add_foreign_key :topic_to_words, :topics
    add_foreign_key :topic_to_words, :words
  end
end
