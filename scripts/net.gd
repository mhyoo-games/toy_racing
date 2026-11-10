extends Node
## 온라인 둘이서 (자동 로드 Net): 브라우저끼리 WebRTC로 바로 잇는다. 게임 서버 없음.
## 방 코드(기본): host_room() → 6자리 방 코드를 친구에게 알려 줌 / 친구: join_room(방 코드)
##   긴 연결 정보(초대·답장)는 공개 메시지 중계(ntfy.sh)의 "toyracing-방코드" 주제로 자동으로 주고받는다.
## 긴 코드(예비): host() → 초대 코드 → 친구 join(초대 코드) → 답장 코드 → 방장 accept()
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

var mode := "room"        ## room(6자리 방 코드) / long(긴 코드 복사)
var room := ""            ## 방 코드
var relay := "https://ntfy.sh/"
var _post: HTTPRequest
var _poll: HTTPRequest
var _poll_t := -1.0
var _poll_busy := false
var _tries := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 웹에서는 HTTPRequest의 timeout이 다 끝난 요청에도 한 번 더 '시간 초과'를 보내므로 쓰지 않고 직접 잰다
	_post = HTTPRequest.new()
	add_child(_post)
	_poll = HTTPRequest.new()
	add_child(_poll)
	_post.request_completed.connect(_on_posted)
	_poll.request_completed.connect(_on_polled)
	if OS.has_feature("web"):
		# 시험용: 주소에 ?relay=http://localhost:8770/ 이면 그 중계를 쓴다
		var r: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('relay')||''", true)
		if str(r) != "":
			relay = str(r) if str(r).ends_with("/") else str(r) + "/"

func _topic() -> String:
	return relay + "toyracing-" + room

## 방 만들기 (6자리 방 코드)
func host_room() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	host()
	mode = "room"
	room = Rules.room_new(rng)

## 방 들어가기 (6자리 방 코드)
func join_room(text: String) -> void:
	var r := Rules.room_clean(text)
	reset()
	mode = "room"
	if r == "":
		error_text = "방 코드는 %d자리예요. 다시 확인해 주세요." % Rules.ROOM_LEN
		role = "join"
		_status("idle")
		return
	room = r
	role = "finding"
	_tries = 0
	_poll_t = 0.01
	_status("finding")

func _send_relay(body: String) -> void:
	_post.cancel_request()
	var err := _post.request(_topic(), ["Content-Type: text/plain"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_relay_fail()
	else:
		_post_wait = 12.0

var _post_wait := -1.0
var _poll_wait := -1.0

func _on_posted(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if _post_wait < 0.0:
		return          # 이미 끝난 요청의 두 번째 알림
	_post_wait = -1.0
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		_relay_fail()

func _on_poll_timeout() -> void:
	_poll_busy = false
	_tries += 1
	if _tries > 3:
		_relay_fail()
	else:
		_poll_t = 2.0

func _relay_fail() -> void:
	error_text = "방 코드 연결 정보를 주고받지 못했어요. 네트워크가 막혀 있을 수 있어요. ‘긴 코드로 연결’을 써 보세요."
	_poll_t = -1.0
	_status("error")

func _poll_now() -> void:
	if _poll_busy:
		return
	_poll_busy = true
	if _poll.request(_topic() + "/json?poll=1&since=all") != OK:
		_poll_busy = false
		_relay_fail()
	else:
		_poll_wait = 12.0

func _on_polled(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if _poll_wait < 0.0:
		return          # 이미 끝난 요청의 두 번째 알림
	_poll_wait = -1.0
	_poll_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		_tries += 1
		if _tries > 3:
			_relay_fail()
		else:
			_poll_t = 2.0
		return
	var text := body.get_string_from_utf8()
	if role == "host" and status == "room":
		var ans := Rules.relay_pick(text, "A:")
		if ans != "" and accept(ans):
			_poll_t = -1.0
			return
		_poll_t = 1.5
	elif role == "finding":
		var offer := Rules.relay_pick(text, "O:")
		if offer != "":
			_poll_t = -1.0
			join(offer)
			return
		_tries += 1
		if _tries > 6:
			error_text = "그 방 코드로 만든 방을 찾지 못했어요. 방장 화면의 코드를 다시 확인해 주세요."
			role = "join"
			_status("idle")
		else:
			_poll_t = 1.5

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
	room = ""
	_poll_t = -1.0
	_poll_busy = false
	_post_wait = -1.0
	_poll_wait = -1.0
	if _post:
		_post.cancel_request()
		_poll.cancel_request()
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
	mode = "long"
	_status("making")
	pc.create_offer()

## 방 들어가기: 초대 코드를 넣는다
func join(code: String) -> bool:
	var d := Rules.net_decode(code)
	if d.is_empty() or d.t != "offer":
		error_text = "초대 코드가 아니에요. 처음부터 끝까지 다 붙여 넣었는지 확인해 주세요."
		changed.emit()
		return false
	var keep_room := room
	var keep_mode := mode
	reset()
	room = keep_room
	mode = keep_mode
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
	# 중계 요청이 너무 오래 걸리면 끊고 실패로
	if _post_wait > 0.0:
		_post_wait -= dt
		if _post_wait <= 0.0:
			_post_wait = -1.0
			_post.cancel_request()
			_relay_fail()
	if _poll_wait > 0.0:
		_poll_wait -= dt
		if _poll_wait <= 0.0:
			_poll_wait = -1.0
			_poll.cancel_request()
			_on_poll_timeout()
	if _poll_t > 0.0:
		_poll_t -= dt
		if _poll_t <= 0.0:
			_poll_now()
	if pc == null:
		return
	pc.poll()
	_since += dt
	if _gather > 0.0:
		_gather -= dt
		if (_gather <= 0.0 or _since > 6.0) and not _desc.is_empty() and my_code == "":
			_gather = -1.0
			my_code = Rules.net_encode(_desc, _cands)
			if mode == "room" and room != "":
				# 방 코드 방식: 긴 정보는 중계로 보내고, 방장은 답장을 기다린다
				_send_relay(("O:" if role == "host" else "A:") + my_code)
				if role == "host":
					_tries = 0
					_poll_t = 2.0
					_status("room")
				else:
					_status("connecting")
			else:
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
