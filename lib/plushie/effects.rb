# frozen_string_literal: true

module Plushie
  # Native platform effect requests.
  #
  # Effects are async operations handled by the renderer: file dialogs,
  # clipboard access, notifications. Each method returns a Command.
  # Results arrive as Event::Effect in update.
  #
  #   def update(model, event)
  #     case event
  #     in Event::Widget[type: :click, id: "open"]
  #       [model, Effects.file_open(title: "Pick a file")]
  #     in Event::Effect[result: [:ok, path]]
  #       model.with(file: path)
  #     end
  #   end
  #
  module Effects
    # TODO: implement
  end
end
