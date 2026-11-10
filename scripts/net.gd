extends Node
## 온라인 둘이서 (자동 로드 Net): 브라우저끼리 WebRTC로 바로 잇는다. 서버 없음.
## 방장: host() → 초대 코드 → 친구에게 보냄 → 친구의 답장 코드를 accept()
## 친구: join(초대 코드) → 답장 코드 → 방장에게 보냄 → 연결
## 채널 둘: ctl(순서·확실, 출발·결과), st(빠름·잃어도 됨, 카트 위치)

signal changed            ## status가 바뀜
signal message(m: Dictionary)

const STUN := ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]

var pc: WebRTCPeerConnection
var ctl: WebRTCDataChannel
var st: WebRTCDataChannel
var role := ""            ## host / guest
var status := "idle"      ## idle → making → code(내 코드 나옴) → connecting → connected / closed / error
var error_text := ""
var my_code := ""
var peer := {}            ## 친구가 알려 준 것 {kart, name}
var _desc := {}
var _cands: Array = []
var _gather := -1.0
var _since := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## 이 환경에서 WebRTC를 쓸 수 있나 (웹에서는 늘, PC판은 확장이 있어야)
func available() -> bool:
	var p := WebRTCPeerConnection.new()
	var ok := p.initialize({}) == OK
	p.close()
	return ok

func connected() -> bool:
	return status == "connected"

func _status(s: String) -> void:
	status = s
	changed.emit()

func reset() -> void:
	if pc:
		pc.close()
	pc = null
	ctl = null
	st = null
	role = ""
	my_code = ""
	peer = {}
	_desc = {}
	_cands = []
	_gather = -1.0
	error_text = ""
	_status("idle")

func _new_pc() -> bool:
	pc = WebRTCPeerConnection.new()
	if pc.initialize({"iceServers": [{"urls": STUN}]}) != OK:
		error_text = "이 브라우저에서는 온라인 연결을 쓸 수 없어요."
		_status("error")
		return false
	pc.session_description_created.connect(func(type: String, sdp: String):
		pc.set_local_description(type, sdp)
		_desc = {"t": type, "s": sdp}
		_gather = 1.5)
	pc.ice_candidate_created.connect(func(media: String, index: int, name: String):
		_cands.append([media, index, name])
		_gather = maxf(_gather, 0.6))
	ctl = pc.create_data_channel("ctl", {"negotiated": true, "id": 1})
	st = pc.create_data_channel("st", {"negotiated": true, "id": 2, "ordered": false, "maxRetransmits": 0})
	_since = 0.0
	return ctl != null and st != null

## 방 만들기
func host() -> void:
	reset()
	role = "host"
	if not _new_pc():
		return
	_status("making")
	pc.create_offer()

## 방 들어가기: 초대 코드를 넣는다
func join(code: String) -> bool:
	var d := Rules.net_decode(code)
	if d.is_empty() or d.t != "offer":
		error_text = "초대 코드가 아니에요. 처음부터 끝까지 다 붙여 넣었는지 확인해 주세요."
		changed.emit()
		return false
	reset()
	role = "guest"
	if not _new_pc():
		return false
	_status("making")
	pc.set_remote_description("offer", d.s)
	for c in d.c:
		pc.add_ice_candidate(c[0], int(c[1]), c[2])
	return true

## 방장이 친구의 답장 코드를 넣는다
func accept(code: String) -> bool:
	var d := Rules.net_decode(code)
	if d.is_empty() or d.t != "answer":
		error_text = "답장 코드가 아니에요. 친구가 보낸 코드를 다 붙여 넣었는지 확인해 주세요."
		changed.emit()
		return false
	error_text = ""
	pc.set_remote_description("answer", d.s)
	for c in d.c:
		pc.add_ice_candidate(c[0], int(c[1]), c[2])
	_since = 0.0
	_status("connecting")
	return true

func _process(dt: float) -> void:
	if pc == null:
		return
	pc.poll()
	_since += dt
	if _gather > 0.0:
		_gather -= dt
		if (_gather <= 0.0 or _since > 6.0) and not _desc.is_empty() and my_code == "":
			_gather = -1.0
			my_code = Rules.net_encode(_desc, _cands)
			_status("code" if role == "host" else "connecting")
	if ctl and ctl.get_ready_state() == WebRTCDataChannel.STATE_OPEN and status != "connected":
		_status("connected")
		send({"y": "me", "kart": Game.save.kart, "name": "방장" if role == "host" else "친구"})
	if status == "connected":
		var gone := pc.get_connection_state() in [WebRTCPeerConnection.STATE_CLOSED, WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_DISCONNECTED] \
			or ctl.get_ready_state() == WebRTCDataChannel.STATE_CLOSED
		if gone:
			_status("closed")
			return
		for ch in [ctl, st]:
			while ch.get_available_packet_count() > 0:
				var p: PackedByteArray = ch.get_packet()
				var j := JSON.new()
				if j.parse(p.get_string_from_utf8()) == OK and typeof(j.data) == TYPE_DICTIONARY:
					var m: Dictionary = j.data
					if m.get("y") == "me":
						peer = m
						changed.emit()
					message.emit(m)
	elif status == "connecting" and pc.get_connection_state() == WebRTCPeerConnection.STATE_FAILED:
		error_text = "연결하지 못했어요. 네트워크가 막혀 있을 수 있어요. 처음부터 다시 해 보세요."
		_status("error")

## fast = 위치처럼 잃어도 되는 것
func send(m: Dictionary, fast := false) -> void:
	if status != "connected":
		return
	var ch := st if fast else ctl
	if ch and ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		ch.put_packet(JSON.stringify(m).to_utf8_buffer())
