# frozen_string_literal: true

require "test_helper"

class TestProtocolEncode < Minitest::Test
  E = Plushie::Protocol::Encode

  def test_encode_settings_json
    result = JSON.parse(E.encode_settings({antialiasing: true, default_text_size: 14}, :json))
    assert_equal "settings", result["type"]
    assert_equal "", result["session"]
    assert_equal 1, result["settings"]["protocol_version"]
    assert_equal true, result["settings"]["antialiasing"]
    assert_equal 14, result["settings"]["default_text_size"]
  end

  def test_encode_settings_msgpack
    data = E.encode_settings({antialiasing: true}, :msgpack)
    result = MessagePack.unpack(data)
    assert_equal "settings", result["type"]
    assert_equal true, result["settings"]["antialiasing"]
  end

  def test_encode_snapshot
    tree = {id: "root", type: "window", props: {}, children: []}
    result = JSON.parse(E.encode_snapshot(tree, :json))
    assert_equal "snapshot", result["type"]
    assert_equal "root", result["tree"]["id"]
  end

  def test_encode_patch
    ops = [{op: "update_props", path: [0], props: {label: "new"}}]
    result = JSON.parse(E.encode_patch(ops, :json))
    assert_equal "patch", result["type"]
    assert_equal 1, result["ops"].length
    assert_equal "update_props", result["ops"][0]["op"]
  end

  def test_encode_subscribe_with_max_rate
    result = JSON.parse(E.encode_subscribe(:on_mouse_move, :mouse, :json, max_rate: 30))
    assert_equal "subscribe", result["type"]
    assert_equal "on_mouse_move", result["kind"]
    assert_equal "mouse", result["tag"]
    assert_equal 30, result["max_rate"]
  end

  def test_encode_subscribe_without_max_rate
    result = JSON.parse(E.encode_subscribe(:on_key_press, :keys, :json))
    refute result.key?("max_rate")
  end

  def test_encode_unsubscribe
    result = JSON.parse(E.encode_unsubscribe(:on_key_press, :json))
    assert_equal "unsubscribe", result["type"]
    assert_equal "on_key_press", result["kind"]
  end

  def test_encode_widget_op
    result = JSON.parse(E.encode_widget_op(:focus, {target: "input1"}, :json))
    assert_equal "widget_op", result["type"]
    assert_equal "focus", result["op"]
    assert_equal "input1", result["payload"]["target"]
  end

  def test_encode_window_op
    result = JSON.parse(E.encode_window_op(:resize, "main", {width: 800, height: 600}, :json))
    assert_equal "window_op", result["type"]
    assert_equal "resize", result["op"]
    assert_equal "main", result["window_id"]
    assert_equal 800, result["settings"]["width"]
  end

  def test_encode_effect
    result = JSON.parse(E.encode_effect("ef_1", "file_open", {title: "Pick"}, :json))
    assert_equal "effect", result["type"]
    assert_equal "ef_1", result["id"]
    assert_equal "file_open", result["kind"]
    assert_equal "Pick", result["payload"]["title"]
  end

  def test_encode_image_op_with_data
    result = JSON.parse(E.encode_image_op("create_image", {handle: "img1", data: "\x89PNG"}, :json))
    assert_equal "image_op", result["type"]
    assert_equal "create_image", result["op"]
    assert_equal "img1", result["handle"]
    refute_nil result["data"]
  end

  def test_encode_image_op_with_pixels
    pixels = "\x00" * 16
    result = JSON.parse(E.encode_image_op("create_image", {handle: "img1", pixels: pixels, width: 2, height: 2}, :json))
    assert_equal 2, result["width"]
    assert_equal 2, result["height"]
    refute_nil result["pixels"]
  end

  def test_encode_extension_command
    result = JSON.parse(E.encode_extension_command("chart-1", "append", {values: [1, 2]}, :json))
    assert_equal "extension_command", result["type"]
    assert_equal "chart-1", result["node_id"]
    assert_equal "append", result["op"]
  end

  def test_encode_extension_commands_batch
    cmds = [
      {node_id: "a", op: "push", payload: {v: 1}},
      {node_id: "b", op: "clear", payload: {}}
    ]
    result = JSON.parse(E.encode_extension_commands(cmds, :json))
    assert_equal "extension_commands", result["type"]
    assert_equal 2, result["commands"].length
  end

  def test_encode_query
    result = JSON.parse(E.encode_query("q1", "find", {by: "id", value: "btn1"}, :json))
    assert_equal "query", result["type"]
    assert_equal "q1", result["id"]
    assert_equal "find", result["target"]
    assert_equal "id", result["selector"]["by"]
  end

  def test_encode_interact
    result = JSON.parse(E.encode_interact("i1", "click", {by: "id", value: "btn"}, {}, :json))
    assert_equal "interact", result["type"]
    assert_equal "i1", result["id"]
    assert_equal "click", result["action"]
  end

  def test_encode_tree_hash
    result = JSON.parse(E.encode_tree_hash("th1", "after_click", :json))
    assert_equal "tree_hash", result["type"]
    assert_equal "th1", result["id"]
    assert_equal "after_click", result["name"]
  end

  def test_encode_screenshot
    result = JSON.parse(E.encode_screenshot("sc1", "homepage", 800, 600, :json))
    assert_equal "screenshot", result["type"]
    assert_equal 800, result["width"]
    assert_equal 600, result["height"]
  end

  def test_encode_reset
    result = JSON.parse(E.encode_reset("r1", :json))
    assert_equal "reset", result["type"]
    assert_equal "r1", result["id"]
  end

  def test_encode_advance_frame
    result = JSON.parse(E.encode_advance_frame(16000, :json))
    assert_equal "advance_frame", result["type"]
    assert_equal 16000, result["timestamp"]
  end

  def test_all_messages_have_session_field
    messages = [
      E.encode_settings({}, :json),
      E.encode_snapshot({}, :json),
      E.encode_patch([], :json),
      E.encode_subscribe(:on_key_press, :k, :json),
      E.encode_unsubscribe(:on_key_press, :json),
      E.encode_widget_op(:focus, {}, :json),
      E.encode_window_op(:close, "w", {}, :json),
      E.encode_effect("e1", "clipboard_read", {}, :json),
      E.encode_image_op("delete_image", {handle: "x"}, :json),
      E.encode_extension_command("n", "op", {}, :json),
      E.encode_extension_commands([], :json),
      E.encode_query("q", "find", {}, :json),
      E.encode_interact("i", "click", nil, {}, :json),
      E.encode_tree_hash("t", "n", :json),
      E.encode_screenshot("s", "n", 100, 100, :json),
      E.encode_reset("r", :json),
      E.encode_advance_frame(0, :json),
      E.encode_register_effect_stub("clipboard_read", {"text" => "hello"}, :json),
      E.encode_unregister_effect_stub("clipboard_read", :json)
    ]
    messages.each do |msg|
      parsed = JSON.parse(msg)
      assert parsed.key?("session"), "Missing session field in: #{parsed["type"]}"
    end
  end

  def test_encode_register_effect_stub
    result = JSON.parse(E.encode_register_effect_stub("clipboard_read", {"text" => "hello"}, :json))
    assert_equal "register_effect_stub", result["type"]
    assert_equal "clipboard_read", result["kind"]
    assert_equal "hello", result["response"]["text"]
  end

  def test_encode_unregister_effect_stub
    result = JSON.parse(E.encode_unregister_effect_stub("file_open", :json))
    assert_equal "unregister_effect_stub", result["type"]
    assert_equal "file_open", result["kind"]
  end
end
