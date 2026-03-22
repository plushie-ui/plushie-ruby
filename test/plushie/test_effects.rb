# frozen_string_literal: true

require "test_helper"

class TestEffects < Minitest::Test
  E = Plushie::Effects

  def test_file_open_returns_command
    cmd = E.file_open(title: "Pick a file")
    assert_equal :effect, cmd.type
    assert_equal "file_open", cmd.payload[:kind]
    assert_equal "Pick a file", cmd.payload[:opts][:title]
    assert_match(/\Aef_/, cmd.payload[:id])
  end

  def test_file_save
    cmd = E.file_save(title: "Save", default_name: "doc.txt")
    assert_equal "file_save", cmd.payload[:kind]
    assert_equal "doc.txt", cmd.payload[:opts][:default_name]
  end

  def test_directory_select
    cmd = E.directory_select(title: "Pick folder")
    assert_equal "directory_select", cmd.payload[:kind]
  end

  def test_clipboard_read
    cmd = E.clipboard_read
    assert_equal "clipboard_read", cmd.payload[:kind]
  end

  def test_clipboard_write
    cmd = E.clipboard_write("hello")
    assert_equal "clipboard_write", cmd.payload[:kind]
    assert_equal "hello", cmd.payload[:opts][:text]
  end

  def test_clipboard_write_html
    cmd = E.clipboard_write_html("<b>bold</b>", alt_text: "bold")
    assert_equal "clipboard_write_html", cmd.payload[:kind]
    assert_equal "<b>bold</b>", cmd.payload[:opts][:html]
    assert_equal "bold", cmd.payload[:opts][:alt_text]
  end

  def test_clipboard_clear
    cmd = E.clipboard_clear
    assert_equal "clipboard_clear", cmd.payload[:kind]
  end

  def test_notification
    cmd = E.notification("Title", "Body", urgency: :critical)
    assert_equal "notification", cmd.payload[:kind]
    assert_equal "Title", cmd.payload[:opts][:title]
    assert_equal "critical", cmd.payload[:opts][:urgency]
  end

  def test_unique_ids
    ids = 10.times.map { E.file_open.payload[:id] }
    assert_equal 10, ids.uniq.length
  end

  def test_default_timeout_file
    assert_equal 120_000, E.default_timeout(:file_open)
    assert_equal 120_000, E.default_timeout("file_save")
  end

  def test_default_timeout_clipboard
    assert_equal 5_000, E.default_timeout(:clipboard_read)
  end

  def test_default_timeout_notification
    assert_equal 5_000, E.default_timeout(:notification)
  end

  def test_custom_timeout
    cmd = E.file_open(title: "test", timeout: 300_000)
    assert_equal 300_000, cmd.payload[:timeout]
    # The opts hash should NOT contain timeout (it's extracted)
    refute cmd.payload[:opts].key?(:timeout)
  end
end
