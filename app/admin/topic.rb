ActiveAdmin.register Topic do
  filter :title
  config.sort_order = 'position_asc' # assumes you are using 'position' for your acts_as_list column
  config.paginate   = false

  sortable

  menu label: proc{"Topics (#{Topic.count})"}

  index do
    sortable_handle_column
    id_column
    column :title
    column :words do |topic|
      topic.words.count
    end
    actions
  end


  form do |f|
    f.inputs 'Topic' do
      f.input :title
      f.input :words, as: :check_boxes, collection: topic.words_for_selection
    end
    f.actions
  end

  show do
    attributes_table do
      row :title
      row  "Words (#{topic.words.count})" do
        topic.words.map(&:to_s).join("<BR>").html_safe
      end
    end
    active_admin_comments
  end

  permit_params :title, :position, word_ids:[]

end
