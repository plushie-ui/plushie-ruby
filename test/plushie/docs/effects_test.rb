# frozen_string_literal: true

require "test_helper"

class DocsEffectsTest < Minitest::Test
  # -- Effects.file_open returns a command --

  def test_effects_file_open_returns_command
    cmd = Plushie::Effects.file_open(
      title: "Choose a file",
      filters: [["Text files", "*.txt"], ["All files", "*"]]
    )
    assert_equal :effect, cmd.type
    assert_equal "file_open", cmd.payload[:kind]
    assert_equal "Choose a file", cmd.payload[:opts][:title]
    assert_equal [["Text files", "*.txt"], ["All files", "*"]], cmd.payload[:opts][:filters]
    assert cmd.payload[:id].start_with?("ef_"), "expected auto-generated effect ID"
  end

  def test_effects_file_open_unique_ids
    cmd1 = Plushie::Effects.file_open(title: "Open")
    cmd2 = Plushie::Effects.file_open(title: "Open")
    refute_equal cmd1.payload[:id], cmd2.payload[:id]
  end

  # -- Effect result pattern matching --

  def test_effects_result_ok_match
    event = Plushie::Event::Effect.new(request_id: "ef_abc123", result: [:ok, {"path" => "/home/user/notes.txt"}])
    case event
    in Plushie::Event::Effect[result: [:ok, data]]
      assert_equal "/home/user/notes.txt", data["path"]
    else
      flunk "expected ok result match"
    end
  end

  def test_effects_result_error_cancelled
    event = Plushie::Event::Effect.new(request_id: "ef_abc123", result: [:error, "cancelled"])
    case event
    in Plushie::Event::Effect[result: [:error, "cancelled"]]
      pass
    else
      flunk "expected cancelled error match"
    end
  end

  # -- Other effect constructors --

  def test_effects_file_save_returns_command
    cmd = Plushie::Effects.file_save(title: "Save as", default_name: "notes.txt")
    assert_equal :effect, cmd.type
    assert_equal "file_save", cmd.payload[:kind]
    assert_equal "notes.txt", cmd.payload[:opts][:default_name]
  end

  def test_effects_clipboard_write_returns_command
    cmd = Plushie::Effects.clipboard_write("hello")
    assert_equal :effect, cmd.type
    assert_equal "clipboard_write", cmd.payload[:kind]
    assert_equal "hello", cmd.payload[:opts][:text]
  end

  def test_effects_clipboard_read_returns_command
    cmd = Plushie::Effects.clipboard_read
    assert_equal :effect, cmd.type
    assert_equal "clipboard_read", cmd.payload[:kind]
  end

  def test_effects_notification_returns_command
    cmd = Plushie::Effects.notification("Alert", "Something happened", urgency: :critical)
    assert_equal :effect, cmd.type
    assert_equal "notification", cmd.payload[:kind]
    assert_equal "Alert", cmd.payload[:opts][:title]
    assert_equal "Something happened", cmd.payload[:opts][:body]
    assert_equal "critical", cmd.payload[:opts][:urgency]
  end

  def test_effects_directory_select_returns_command
    cmd = Plushie::Effects.directory_select(title: "Pick a folder")
    assert_equal :effect, cmd.type
    assert_equal "directory_select", cmd.payload[:kind]
  end

  # -- Update integration pattern --

  def test_effects_update_pattern
    # Simulate the pattern from the effects doc:
    # click -> return [model, file_open command]
    # effect response -> update model
    model = {file_path: nil}

    # Step 1: user clicks open_file
    _click = Plushie::Event::Widget.new(type: :click, id: "open_file")
    cmd = Plushie::Effects.file_open(title: "Choose a file", filters: [["Text files", "*.txt"]])
    result = [model, cmd]
    assert_equal :effect, result[1].type

    # Step 2: effect result arrives
    effect_event = Plushie::Event::Effect.new(
      request_id: cmd.payload[:id],
      result: [:ok, {"path" => "/tmp/notes.txt"}]
    )
    case effect_event
    in Plushie::Event::Effect[result: [:ok, data]]
      model = model.merge(file_path: data["path"])
    end
    assert_equal "/tmp/notes.txt", model[:file_path]
  end
end
