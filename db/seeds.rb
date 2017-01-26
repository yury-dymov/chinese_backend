# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

if Topic.count == 0
  topic = ActiveSupport::JSON.decode(File.read(Rails.root.to_s + "/db/seeds/topic.json"))
  topic.each {|elem| Topic.create(elem) }
end

if Word.count == 0
  topic = ActiveSupport::JSON.decode(File.read(Rails.root.to_s + "/db/seeds/word.json"))
  topic.each {|elem| Word.create(elem) }
end

if TopicToWord.count == 0
  topic = ActiveSupport::JSON.decode(File.read(Rails.root.to_s + "/db/seeds/topic_to_word.json"))
  topic.each {|elem| TopicToWord.create(elem) }
end