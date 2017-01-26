ActiveAdmin.register Word do
  filter :native
  filter :transcription
  filter :translation
  remove_filter :topics
#  filter :association, as: :select, collection: -> {Topic.pluck(:title, :id)}
  
menu label: proc{"Words (#{Word.count})"}

action_item :view, only: :show do
  link_to 'New Word', new_admin_word_path
end

collection_action :translate, method: :post do

end

controller do
  def scoped_collection
    super.includes :topics
  end

  def new
    @word = Word.new
    @word.topics << Topic.new
  end
end

form do |f|
  f.inputs 'Word' do
    f.input :native
    f.input :transcription
    f.input :translation
  end
  f.inputs 'Topics' do
    f.has_many :topic_to_words, allow_destroy: true do |t|
      t.input :topic_id, :as => :select, :collection => Topic.all.collect {|product| [product.title, product.id] }
    end
  end
  f.actions
end

index do
  id_column
  column :native
  column :transcription
  column :translation
  column :topics do |word|
    word.topics.map {|t| t.title}.join(", ")
  end
  actions
end

show do
  attributes_table do
    row :native
    row :transcription
    row :translation
    row :topics do
      word.topics.map {|t| t.title}.join(", ")
    end
  end
  active_admin_comments
end

permit_params :native, :transcription, :translation, topic_to_words_attributes: [:topic_id, :word_id, :_destroy, :id]

end
