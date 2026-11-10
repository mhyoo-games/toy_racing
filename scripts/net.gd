extends Node
## 온라인 (자동 로드 Net): 브라우저끼리 WebRTC로 바로 잇는다. 게임 서버 없음. 최대 8명.
##
## 방 코드(기본): 방장이 host_room() → 6자리 방 코드. 친구들이 join_room(방 코드).
##   방장이 가운데: 친구마다 따로 연결하고, 친구들의 카트 상태를 모아 모두에게 나눠 준다.
##   처음 연결 정보는 공개 메시지 중계(ntfy.sh)의 "toyracing-방코드" 주제로 주고받는다:
##     친구 → "J:<gid>"(들어가고 싶어요)   방장 → "O:<gid>:<초대>"   친구 → "A:<gid>:<답장>"   방장 → "X:<gid>"(가득 참)
##   웹에서는 EventSource(SSE)로 새 글을 바로 받는다(요청 한 번). 웹이 아니면 몇 초마다 읽는다.
## 긴 코드(예비, 둘이서만): host() → 초대 코드 → 친구 join(초대 코드) → 답장 코드 → 방장 accept()
## 채널 둘: ctl(순서·확실: hello·me·roster·go·fin·bye), st(빠름·잃어도 됨: 카트 위치 s)
## message 신호의 m.from = 보낸 사람 번호(pid). 방장 0, 친구 1~7.

signal changed            ## status·참가자가 바뀜
signal message(m: Dictionary)

const STUN := ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]
const MAX_PLAYERS := 8

var role := ""            ## host / guest / (화면용: join, longjoin, finding)
var status := "idle"      ## idle, room(방장 대기실), finding(친구가 방 찾는 중), making, code(긴 코드 방장), connecting, connected, closed, error
var mode := "room"        ## room / long
var error_text := ""
var room := ""
var relay := "https://ntfy.sh/"
var my_pid := -1
var my_code := ""         ## 긴 코드 방식에서 보여 줄 코드
var roster: Array = []    ## [{pid, kart, name}] — 방장이 정해 모두에게 보낸다
var locked := false       ## 경주 중이면 새로 받지 않는다

var peers := {}           ## gid → {pc, ctl, st, desc, cands, gather, since, pid, open, code_sent}
var my_gid := ""          ## 친구 쪽 내 번호
var _seen := {}           ## 이미 읽은 중계 글 id
var _next_pid := 1
var _sse := false
var _poll: HTTPRequest
var _poll_t := -1.0
var _poll_busy := false
var _poll_wait := -1.0
var _post: HTTPRequest
var _post_q: Array = []
var _post_wait := -1.0
var _find_t := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 웹에서는 HTTPRequest의 timeout이 끝난 요청에도 '시간 초과'를 한 번 더 보내므로 쓰지 않고 직접 잰다
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
		JavaScriptBridge.eval("""
			window.__trsse = window.__trsse || {
				q: [], es: null, err: 0,
				open: function(url) {
					this.close(); this.q = []; this.err = 0;
					var self = this;
					try { this.es = new EventSource(url); } catch (x) { this.err = 99; return; }
					this.es.onmessage = function(e) {
						try { var d = JSON.parse(e.data); if (!d.event || d.event === 'message') self.q.push({id: d.id, m: d.message || ''}); } catch (x) {}
					};
					this.es.onerror = function() { self.err++; };
				},
				take: function() { var a = this.q; this.q = []; return JSON.stringify(a); },
				close: function() { if (this.es) this.es.close(); this.es = null; }
			};
		""", true)

## 이 환경에서 WebRTC를 쓸 수 있나 (웹에서는 늘, PC판은 확장이 있어야)
func available() -> bool:
	var p := WebRTCPeerConnection.new()
	var ok := p.initialize({}) == OK
	p.close()
	return ok

func connected() -> bool:
	if role == "host":
		for g in peers:
			if peers[g].open:
				return true
		return false
	return status == "connected"

func is_host() -> bool:
	return role == "host"

func _status(s: String) -> void:
	status = s
	changed.emit()

func reset() -> void:
	for g in peers:
		if peers[g].pc:
			peers[g].pc.close()
	peers = {}
	role = ""
	mode = "room"
	my_pid = -1
	my_gid = ""
	my_code = ""
	roster = []
	room = ""
	locked = false
	error_text = ""
	_seen = {}
	_next_pid = 1
	_poll_t = -1.0
	_poll_busy = false
	_poll_wait = -1.0
	_post_q = []
	_post_wait = -1.0
	_find_t = -1.0
	_sse_close()
	if _post:
		_post.cancel_request()
		_poll.cancel_request()
	_status("idle")

# ─────────── 연결 하나 (친구 한 명) ───────────

func _new_peer(gid: String) -> Dictionary:
	var pc := WebRTCPeerConnection.new()
	if pc.initialize({"iceServers": [{"urls": STUN}]}) != OK:
		error_text = "이 브라우저에서는 온라인 연결을 쓸 수 없어요."
		_status("error")
		return {}
	var p := {"pc": pc, "ctl": null, "st": null, "desc": {}, "cands": [], "gather": -1.0, "since": 0.0, "pid": -1, "open": false, "code_sent": false, "answered": false}
	pc.session_description_created.connect(_on_desc.bind(gid))
	pc.ice_candidate_created.connect(_on_cand.bind(gid))
	p.ctl = pc.create_data_channel("ctl", {"negotiated": true, "id": 1})
	p.st = pc.create_data_channel("st", {"negotiated": true, "id": 2, "ordered": false, "maxRetransmits": 0})
	peers[gid] = p
	return p

func _on_desc(type: String, sdp: String, gid: String) -> void:
	if not peers.has(gid):
		return
	var p: Dictionary = peers[gid]
	p.pc.set_local_description(type, sdp)
	p.desc = {"t": type, "s": sdp}
	p.gather = 1.5

func _on_cand(media: String, index: int, cname: String, gid: String) -> void:
	if not peers.has(gid):
		return
	var p: Dictionary = peers[gid]
	p.cands.append([media, index, cname])
	p.gather = maxf(float(p.gather), 0.6)

func _apply_remote(p: Dictionary, d: Dictionary) -> void:
	p.pc.set_remote_description(d.t, d.s)
	for c in d.c:
		p.pc.add_ice_candidate(c[0], int(c[1]), c[2])

# ─────────── 방 코드 ───────────

func _topic() -> String:
	return relay + "toyracing-" + room

## 방 만들기 (6자리 방 코드). 방장은 바로 대기실
func host_room() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	reset()
	role = "host"
	mode = "room"
	room = Rules.room_new(rng)
	my_pid = 0
	roster = [{"pid": 0, "kart": Game.save.kart, "name": "방장"}]
	_listen()
	_status("room")

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
	role = "guest"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	my_gid = Rules.room_new(rng).substr(0, 4)
	_listen()
	_send_relay("J:" + my_gid)
	_find_t = 15.0
	_status("finding")

## 중계 듣기 시작 (웹: SSE, 아니면 몇 초마다 읽기)
func _listen() -> void:
	_sse = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__trsse.open(%s)" % JSON.stringify(_topic() + "/sse?since=all"), true)
		_sse = true
	else:
		_poll_t = 0.2

func _sse_close() -> void:
	if OS.has_feature("web") and _sse:
		JavaScriptBridge.eval("window.__trsse && window.__trsse.close()", true)
	_sse = false

func _send_relay(body: String) -> void:
	_post_q.append(body)
	_pump_post()

func _pump_post() -> void:
	if _post_wait > 0.0 or _post_q.is_empty():
		return
	var body: String = _post_q.pop_front()
	if _post.request(_topic(), ["Content-Type: text/plain"], HTTPClient.METHOD_POST, body) != OK:
		_relay_fail()
	else:
		_post_wait = 12.0

func _on_posted(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if _post_wait < 0.0:
		return          # 이미 끝난 요청의 두 번째 알림
	_post_wait = -1.0
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		_relay_fail()
		return
	_pump_post()

func _relay_fail() -> void:
	error_text = "방 코드 연결 정보를 주고받지 못했어요. 네트워크가 막혀 있을 수 있어요. ‘긴 코드로 연결’을 써 보세요."
	_poll_t = -1.0
	_sse_close()
	_status("error")

func _poll_now() -> void:
	if _poll_busy:
		return
	_poll_busy = true
	if _poll.request(_topic() + "/json?poll=1&since=all") != OK:
		_poll_busy = false
		_poll_t = 4.0
	else:
		_poll_wait = 12.0

func _on_polled(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if _poll_wait < 0.0:
		return
	_poll_wait = -1.0
	_poll_busy = false
	_poll_t = 3.0
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		return
	for item in Rules.relay_list(body.get_string_from_utf8()):
		_relay_msg(str(item.id), str(item.m))

## 중계 글 하나 처리
func _relay_msg(id: String, text: String) -> void:
	if _seen.has(id):
		return
	_seen[id] = true
	var parts := text.split(":", true, 2)
	if parts.size() < 2:
		return
	var kind := parts[0]
	var gid := parts[1]
	if role == "host" and mode == "room":
		if kind == "J" and not peers.has(gid):
			if locked or roster.size() + _pending() >= MAX_PLAYERS:
				_send_relay("X:" + gid)
			else:
				var p := _new_peer(gid)
				if not p.is_empty():
					p.pc.create_offer()
		elif kind == "A" and peers.has(gid) and parts.size() == 3 and not peers[gid].answered:
			var d := Rules.net_decode(parts[2])
			if not d.is_empty():
				peers[gid].answered = true
				_apply_remote(peers[gid], d)
	elif role == "guest" and gid == my_gid:
		if kind == "O" and parts.size() == 3 and not peers.has("host"):
			var d2 := Rules.net_decode(parts[2])
			if d2.is_empty():
				return
			var p2 := _new_peer("host")
			if p2.is_empty():
				return
			_apply_remote(p2, d2)
			_find_t = -1.0
			_status("connecting")
		elif kind == "X":
			error_text = "방이 가득 찼거나 이미 경주 중이에요."
			_sse_close()
			role = "join"
			_status("idle")

## 연결 중(아직 안 열린) 친구 수
func _pending() -> int:
	var n := 0
	for g in peers:
		if not peers[g].open:
			n += 1
	return n

# ─────────── 긴 코드 (둘이서만) ───────────

func host() -> void:
	reset()
	role = "host"
	mode = "long"
	my_pid = 0
	roster = [{"pid": 0, "kart": Game.save.kart, "name": "방장"}]
	var p := _new_peer("L")
	if p.is_empty():
		return
	_status("making")
	p.pc.create_offer()

func join(code: String) -> bool:
	var d := Rules.net_decode(code)
	if d.is_empty() or d.t != "offer":
		error_text = "초대 코드가 아니에요. 처음부터 끝까지 다 붙여 넣었는지 확인해 주세요."
		changed.emit()
		return false
	reset()
	role = "guest"
	mode = "long"
	var p := _new_peer("host")
	if p.is_empty():
		return false
	_status("making")
	_apply_remote(p, d)
	return true

func accept(code: String) -> bool:
	var d := Rules.net_decode(code)
	if d.is_empty() or d.t != "answer" or not peers.has("L"):
		error_text = "답장 코드가 아니에요. 친구가 보낸 코드를 다 붙여 넣었는지 확인해 주세요."
		changed.emit()
		return false
	error_text = ""
	_apply_remote(peers["L"], d)
	_status("connecting")
	return true

# ─────────── 매 프레임 ───────────

func _process(dt: float) -> void:
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
			_poll_busy = false
			_poll_t = 3.0
	if _poll_t > 0.0:
		_poll_t -= dt
		if _poll_t <= 0.0:
			_poll_now()
	if _sse:
		var raw: Variant = JavaScriptBridge.eval("window.__trsse.take()", true)
		var j := JSON.new()
		if typeof(raw) == TYPE_STRING and j.parse(raw) == OK and typeof(j.data) == TYPE_ARRAY:
			for item in j.data:
				_relay_msg(str(item.get("id", "")), str(item.get("m", "")))
		var err: Variant = JavaScriptBridge.eval("window.__trsse.err", true)
		if int(err) > 8 and status in ["finding", "room"] and peers.is_empty():
			_relay_fail()
	if _find_t > 0.0:
		_find_t -= dt
		if _find_t <= 0.0 and status == "finding":
			error_text = "그 방 코드로 만든 방을 찾지 못했어요. 방장 화면의 코드를 다시 확인해 주세요."
			_sse_close()
			role = "join"
			_status("idle")
	for gid in peers.keys():
		_peer_tick(gid, dt)

func _peer_tick(gid: String, dt: float) -> void:
	var p: Dictionary = peers[gid]
	var pc: WebRTCPeerConnection = p.pc
	pc.poll()
	p.since = float(p.since) + dt
	# 연결 정보가 다 모이면 코드로 만들어 보낸다
	if float(p.gather) > 0.0:
		p.gather = float(p.gather) - dt
		if (float(p.gather) <= 0.0 or float(p.since) > 6.0) and not p.desc.is_empty() and not p.code_sent:
			p.gather = -1.0
			p.code_sent = true
			var code := Rules.net_encode(p.desc, p.cands)
			if mode == "room":
				_send_relay(("O:" if role == "host" else "A:") + (gid if role == "host" else my_gid) + ":" + code)
			else:
				my_code = code
				_status("code" if role == "host" else "connecting")
	var ctl: WebRTCDataChannel = p.ctl
	if not p.open and ctl.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		p.open = true
		if role == "host":
			p.pid = _next_pid
			_next_pid += 1
			_send_to(p, {"y": "hello", "pid": p.pid})
			roster.append({"pid": p.pid, "kart": "acorn", "name": "친구 %d" % p.pid})
			_broadcast_roster()
			if status != "room":
				_status("room")
			else:
				changed.emit()
		else:
			_status("connected")
	if p.open:
		var gone := pc.get_connection_state() in [WebRTCPeerConnection.STATE_CLOSED, WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_DISCONNECTED] \
			or ctl.get_ready_state() == WebRTCDataChannel.STATE_CLOSED
		if gone:
			_drop(gid)
			return
		for ch in [p.ctl, p.st]:
			while (ch as WebRTCDataChannel).get_available_packet_count() > 0:
				var pkt: PackedByteArray = (ch as WebRTCDataChannel).get_packet()
				var jj := JSON.new()
				if jj.parse(pkt.get_string_from_utf8()) == OK and typeof(jj.data) == TYPE_DICTIONARY:
					_got(p, jj.data)
	elif float(p.since) > 40.0 or pc.get_connection_state() == WebRTCPeerConnection.STATE_FAILED:
		# 끝내 안 열린 연결은 버린다
		if role == "host":
			pc.close()
			peers.erase(gid)
			changed.emit()
		else:
			error_text = "연결하지 못했어요. 네트워크가 막혀 있을 수 있어요. 처음부터 다시 해 보세요."
			_status("error")

func _drop(gid: String) -> void:
	var p: Dictionary = peers[gid]
	p.pc.close()
	peers.erase(gid)
	if role == "host":
		var pid: int = p.pid
		roster = roster.filter(func(e): return int(e.pid) != pid)
		_broadcast_roster()
		message.emit({"y": "left", "pid": pid, "from": pid})
		changed.emit()
	else:
		_status("closed")

## 받은 것
func _got(p: Dictionary, m: Dictionary) -> void:
	if role == "host":
		m["from"] = p.pid
		if m.get("y") == "me":
			for e in roster:
				if int(e.pid) == int(p.pid):
					e.kart = str(m.get("kart", "acorn"))
			_broadcast_roster()
			changed.emit()
	else:
		m["from"] = 0
		match m.get("y"):
			"hello":
				my_pid = int(m.pid)
				send({"y": "me", "kart": Game.save.kart})
				changed.emit()
			"roster":
				roster = m.get("list", [])
				changed.emit()
	message.emit(m)

func _broadcast_roster() -> void:
	send({"y": "roster", "list": roster})

func _send_to(p: Dictionary, m: Dictionary, fast := false) -> void:
	if not p.open:
		return
	var ch: WebRTCDataChannel = p.st if fast else p.ctl
	if ch and ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		ch.put_packet(JSON.stringify(m).to_utf8_buffer())

## 보내기. 방장: 모두에게(to = 특정 pid만, except = 이 pid 빼고). 친구: 방장에게.
## fast = 위치처럼 잃어도 되는 것
func send(m: Dictionary, fast := false, to := -1, except := -1) -> void:
	for g in peers:
		var p: Dictionary = peers[g]
		if role == "host":
			if to >= 0 and int(p.pid) != to:
				continue
			if except >= 0 and int(p.pid) == except:
				continue
		_send_to(p, m, fast)

## 내 카트를 바꾸면 알린다 (방장은 직접 목록을 고친다)
func my_kart_changed(kart: String) -> void:
	if role == "host":
		for e in roster:
			if int(e.pid) == 0:
				e.kart = kart
		_broadcast_roster()
		changed.emit()
	elif connected():
		send({"y": "me", "kart": kart})
