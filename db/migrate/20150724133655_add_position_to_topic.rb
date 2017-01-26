class AddPositionToTopic < ActiveRecord::Migration
  def change
    add_column :topics, :position, :integer
    Topic.all.each do |topic|
      topic.position = topic.id
      topic.save
    end
  end
end
