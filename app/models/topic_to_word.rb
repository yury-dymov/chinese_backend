class TopicToWord < ActiveRecord::Base
  has_modata
  belongs_to :topic
  belongs_to :word

end
