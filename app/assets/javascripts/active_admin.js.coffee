#= require active_admin/base
#= require activeadmin-sortable

ready = ->
  $('#edit_word, #new_word').find('#word_native').bind 'blur', ->
    text = $(this).val()
    if text.length > 0
      $.post "/admin/words/translate", {word: text, from: "zh", to: "ru"}, null, "script"
  $('#edit_word, #new_word').find('#word_translation').bind 'blur', ->
    text = $(this).val()
    if text.length > 0 && $('#edit_word, #new_word').find('#word_native').val().length == 0
      $.post "/admin/words/translate", {word: text, from: "ru", to: "zh"}, null, "script"
  $(document).mouseup ->
    if $('#edit_topic').length > 0 || $('#new_topic').length > 0
      if document.getSelection().toString().trim().length > 0
        words = document.getSelection().toString().split("\n").filter (n) ->
          return n.trim().length != 0 && n.split("|").length > 1
        words_index = 0
        $('#topic_words_input label').each (index, value)->
          if words_index == words.length
            return
          if $(value).text().indexOf(words[words_index].split("|")[0]) >= 0
            words_index++
            if words.length == words_index
              initial = index - words_index
              $('#topic_words_input label').each (index, value)->
                if index > initial && index <= words_index + initial
                  $(value).find('input').prop('checked', true)
              return
          else
            words_index = 0
            if $(value).text().indexOf(words[words_index]) >= 0
              words_index = 1

$(document).ready(ready)
$(document).on('page:load', ready)
$(document).on("page:change", ready)
