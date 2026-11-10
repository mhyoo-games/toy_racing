class_name CodeBox
extends Control
## 연결 코드 상자. 웹에서는 진짜 HTML textarea를 그 자리에 띄워 복사·붙여넣기가 (휴대폰에서도) 잘 되게 한다.
## 웹이 아니면 Godot TextEdit.

static var _n := 0

var readonly := false
var placeholder := ""
var dom_id := ""
var edit: TextEdit
var _text := ""

func _ready() -> void:
	_n += 1
	dom_id = "trcode%d" % _n
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			(function(){
				var t = document.createElement('textarea');
				t.id = '%s';
				t.spellcheck = false;
				t.placeholder = %s;
				t.readOnly = %s;
				t.style.cssText = 'position:fixed;z-index:10;box-sizing:border-box;resize:none;font:13px monospace;' +
					'background:#fff8e6;color:#2a1c12;border:3px solid #8a5a33;border-radius:10px;padding:8px;word-break:break-all;';
				t.value = %s;
				document.body.appendChild(t);
			})();
		""" % [dom_id, JSON.stringify(placeholder), "true" if readonly else "false", JSON.stringify(_text)], true)
	else:
		edit = TextEdit.new()
		edit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.editable = not readonly
		edit.placeholder_text = placeholder
		edit.text = _text
		add_child(edit)

func _exit_tree() -> void:
	if OS.has_feature("web") and dom_id != "":
		JavaScriptBridge.eval("var e=document.getElementById('%s'); if(e) e.remove();" % dom_id, true)

func _process(_dt: float) -> void:
	if not OS.has_feature("web") or dom_id == "":
		return
	# 화면(Godot) 좌표 → 창 비율로 자리 맞추기
	var vp := get_viewport().get_visible_rect().size
	var r := get_global_rect()
	var vis := is_visible_in_tree()
	JavaScriptBridge.eval("var e=document.getElementById('%s'); if(e){e.style.left='%.3f%%';e.style.top='%.3f%%';e.style.width='%.3f%%';e.style.height='%.3f%%';e.style.display='%s';e.style.opacity='%.2f';}" % [
		dom_id, r.position.x / vp.x * 100.0, r.position.y / vp.y * 100.0, r.size.x / vp.x * 100.0, r.size.y / vp.y * 100.0, "block" if vis else "none", modulate.a], true)

func set_text(t: String) -> void:
	_text = t
	if OS.has_feature("web") and dom_id != "":
		JavaScriptBridge.eval("var e=document.getElementById('%s'); if(e) e.value=%s;" % [dom_id, JSON.stringify(t)], true)
	elif edit:
		edit.text = t

func get_text() -> String:
	if OS.has_feature("web") and dom_id != "":
		var v: Variant = JavaScriptBridge.eval("(document.getElementById('%s')||{}).value||''" % dom_id, true)
		return str(v)
	if edit:
		return edit.text
	return _text

## 클립보드로 복사 (웹: 브라우저 클립보드, 안 되면 글자를 골라 둔다)
func copy() -> void:
	if OS.has_feature("web") and dom_id != "":
		JavaScriptBridge.eval("""
			(function(){
				var e=document.getElementById('%s'); if(!e) return;
				e.focus(); e.select(); e.setSelectionRange(0, e.value.length);
				var ok=false; try { ok=document.execCommand('copy'); } catch(x) {}
				if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(e.value).catch(function(){});
			})();
		""" % dom_id, true)
	else:
		DisplayServer.clipboard_set(get_text())

## 붙여넣기 (웹: 브라우저가 허락하면 클립보드에서 읽어 상자에 넣는다)
func paste() -> void:
	if OS.has_feature("web") and dom_id != "":
		JavaScriptBridge.eval("""
			(function(){
				var e=document.getElementById('%s'); if(!e) return;
				if (navigator.clipboard && navigator.clipboard.readText)
					navigator.clipboard.readText().then(function(t){ e.value=t; }).catch(function(){ e.focus(); });
				else e.focus();
			})();
		""" % dom_id, true)
	else:
		set_text(DisplayServer.clipboard_get())

func focus() -> void:
	if OS.has_feature("web") and dom_id != "":
		JavaScriptBridge.eval("var e=document.getElementById('%s'); if(e) e.focus();" % dom_id, true)
	elif edit:
		edit.grab_focus()
