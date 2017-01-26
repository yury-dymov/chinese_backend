class Word < ActiveRecord::Base
  has_modata
  
  has_many :topic_to_words, dependent: :destroy  
  has_many :topics, through: :topic_to_words
  
  accepts_nested_attributes_for :topic_to_words, allow_destroy: true
  
  validates_presence_of :native, :transcription, :translation  
  
  def to_s
    "#{native} | #{transcription} | #{translation}"
  end
end
