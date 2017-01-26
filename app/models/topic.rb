class Topic < ActiveRecord::Base
  has_modata
  acts_as_list

  has_many :topic_to_words, dependent: :destroy
  has_many :words, through: :topic_to_words

  accepts_nested_attributes_for :topic_to_words, allow_destroy: true
  accepts_nested_attributes_for :words, allow_destroy: true

  validates_presence_of :title
  validates_uniqueness_of :title

  def words_for_selection
    ret = [self.words]
    ret << Word.order("id DESC").where.not(id: self.words.map {|word| word.id})
    ret.flatten
  end
end
