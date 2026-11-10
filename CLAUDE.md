# 이 저장소에서 작업할 때 지킬 것

유민혁(minhyuk94)의 개인 프로젝트 "토이 레이싱". 사용자는 한국어로 대화합니다. 게임 글자도 한국어.

## 무엇인가

숲속 장난감 카트 3D 레이싱 (경주·혼자 연습·둘이서 화면 나누기·친구와 온라인, 스피드전/아이템전, 카트 상점, 트랙 6개). Godot 4.6(GDScript, GL Compatibility), 웹으로 내보내 GitHub Pages(`https://mhyoo-games.github.io/toy_racing/`, 조직 mhyoo-games)에 올린다.

## 지킬 것

- 옛 온라인 카트 레이싱에서 영감을 받았지만 **새로 만든 게임**이다. 다른 게임의 이름·캐릭터·카트·트랙·그림·음악을 쓰지 않고, 다른 회사·게임 이름을 README·화면·이력서에 넣지 않는다.
- 그림: Kenney Mini Forest(CC0, `assets/forest/LICENSE.txt`)를 트랙 꾸밈·운전수(`character-archer.glb`의 `drive` 동작)로 쓰고, 카트·도로·연석·출발 문은 코드로 만든다(`scripts/kart.gd`, `scripts/track_view.gd`). 글꼴: 갈무리(OFL).
- 드리프트 소리: 거는 순간 `screech`(끼이익 한 번), 미끄러지는 동안 `skid` 반복 — 미끄러짐 각×속도로 크기·높이가 바뀐다(`Sound.skid`).
- 곡: `title`, `race`, `rush`(긴박, 마지막 바퀴에 바뀜). `song()`이 구역별 멜로디·화음·16칸 북 패턴·펌핑 베이스·아르페지오를 합성. 소리는 QOA로 압축되므로 반복 끝(loop_end)은 `get_length() × mix_rate`로 잡는다(`data.size()`가 아님).
- 소리: `tools/sound/gen.py`가 표준 라이브러리로 합성 → `assets/sfx`, `assets/music`. 결과 wav를 직접 고치지 말고 생성기를 고친다. 아이콘은 `tools/art/icon.py`.
- 규칙(계산)은 `scripts/rules.gd`에 화면과 떨어뜨려 모은다: 카트 물리(좌표 `Vector2(x, z)`, yaw 0 = +z, 오른쪽 핸들 = yaw 감소. 속도는 크기와 방향으로 나누고, 핸들은 코를 돌리고 가는 방향은 접지력만큼 코를 따라간다. 핸들 입력은 `STEER_IN/OUT`으로, 회전 속도는 응답 빠르기로 부드럽게), 드리프트(접지력 `DRIFT_GRIP`으로 미끄러짐 각이 저절로 생김 ≈ 회전 속도/접지력, 손을 떼면 천천히·카운터면 빨리 펴짐), 끌기(드리프트 키를 누른 채로도 방향키가 다 먹음: 반대쪽은 코를 되돌리고, 넘어가면 `drift_flip`으로 반대쪽 드리프트), 톡톡이(드리프트 중 키를 다시 누르면 `TAP_KICK` 만큼 더 돌고 `TAP_CHUNK` 게이지 덤, `TAP_COOLDOWN`마다 한 번 — 드리프트를 걸 때도 같은 덤), 끊어 타기(드리프트가 끝난 뒤 접지가 `RECOVER_TIME`에 걸쳐 돌아와 짧게 끊어 치면 속도를 안 잃고 방향만 꺾임), 부스터 중 드리프트는 게이지 `BOOST_GAUGE`배, 카트 드리프트 능력 3(처음 카트)~9 → 게이지 두 배 차이, 후진 드리프트(뒤로 가며 드리프트 키 + 방향키로 크게 돎), 브레이크 드리프트(드리프트 중 ↓: 급브레이크 대신 더 크게 돎), 순간부스터 기회는 펴지기 시작할 때(`win_open`)부터 열리고 `MINI_EARLY`만큼 일찍 누른 것도 인정, 커팅(직선에서 좌우로 톡톡 쳐 앞으로 가며 게이지 모으기 — 작은 미끄러짐에도 게이지가 차고 가속은 거의 그대로), 게이지·부스터(두 개까지), 순간부스터(드리프트 끝난 뒤 `MINI_WINDOW` 안에 가속 다시 누르기), 출발 부스터, 잔디 감속(부스터면 덜 느림 = 부스터 지름길), 울타리, 랩·순위, 레이싱 라인, 컴퓨터 입력, 보상·상점·저장. 새 규칙에는 `tests/run_tests.gd`에 테스트를 더한다. 조작감은 `_smooth_feel`(핸들·회전이 튀지 않음, 미끄러짐 각 범위, 톡톡이가 핸들보다 더 꺾이고 속도 유지)과 `_drift_tricks`(끌기 게이지, 누른 채 카운터·반대쪽으로 이어가기, 사람처럼 친 커팅이 앞으로 가며 게이지를 모음)·`_gauge_balance`(톡톡이 > 끌기, 부스터 중 더, 연타 한도, 카트별 차이, 후진 드리프트) 테스트로 지킨다 — 숫자를 바꾸면 여기와 컴퓨터 3바퀴 테스트를 같이 본다.
- 트랙은 `data/tracks.json`(조절점 [x, z] 또는 [x, z, 높이]·폭·`music`·`theme`). 높이가 `BRIDGE_H`를 넘는 곳은 다리: 잔디 없이 난간(`walls`), 옆면·기둥(`track_view._bridges`, 다른 길 위에는 기둥 안 세움). 교차(위아래 층)는 `locate`의 hint(가까운 번호만 봄)와 높이 y로 층을 구분하고, 카트끼리·상자·함정은 높이 차가 크면 안 부딪힌다. 카트 높이·기울기는 `race._set_height`.
- 아이템전(`scripts/race_items.gd`, 규칙은 `Rules.item_roll/give_item/hit/ai_use_item`): 상자 5줄×6개, 아이템 두 칸, 부스터 키로 사용, 맞으면 `spin_t` 동안 빙글(조작 안 됨), 방패는 한 번 막음, 아이템전은 `no_gauge`(드리프트 게이지 없음). 온라인은 아직 스피드전만.
- 트랙을 바꾸면 테스트(컴퓨터가 3바퀴를 벽에 거의 안 박고 도는지, 출발 자리가 도로 위인지)가 통과해야 한다. 카트는 `data/karts.json`(능력치 1~10, 값 순서).
- 컴퓨터 상대는 사람 카트의 능력치를 기준으로 달린다(`Rules.ai_stats`) — 카트 종류는 겉모양만. 너무 어렵지 않게.
- 저장은 `user://toy_racing_save.json` 하나 (`Rules.parse_save`가 망가진 값도 받아 준다).
- Godot 4.6은 Variant에서 `:=`로 타입을 추론하면 오류다. 딕셔너리 값은 `var x: float = d.y`처럼 타입을 적는다. `Node`의 `tr()`과 이름이 겹치므로 트랙 변수는 `trk`.
- CanvasLayer 아래 Control은 창의 theme을 못 물려받는다 → 기본 글꼴은 `project.godot`의 `gui/theme/custom_font`(갈무리)로. 오른쪽 붙이기는 `set_anchors_preset` 뒤 offset을 직접 준다.
- 온라인(`scripts/net.gd`, 자동 로드 Net): WebRTC, 최대 8명(`MAX_PLAYERS`), 방장이 가운데인 별 모양(친구끼리는 직접 안 이음, 방장이 `send(m, fast, to, except)`로 전함). 기본은 6자리 방 코드(`Rules.room_new/room_clean`, 헷갈리는 글자 뺌) — 공개 메시지 중계 ntfy.sh의 `toyracing-<방코드>` 주제로 연결 정보를 주고받는다: 친구 `J:<gid>` → 방장 `O:<gid>:<초대>` → 친구 `A:<gid>:<답장>` (`X`는 꽉 참/닫힘). 웹은 SSE(EventSource, `window.__trsse`)로 듣고, 아니면 3초마다 `json?poll=1&since=all`(`Rules.relay_pick`). 웹의 HTTPRequest는 끝난 요청에도 시간 초과 알림을 한 번 더 보내므로 timeout을 쓰지 않고 직접 잰다. 연결되면 방장이 번호(`pid`, 방장 0)를 주고 `roster`(pid·카트·이름)를 모두에게 보낸다. 출발하면 `locked`. 중계가 막히면 예비로 긴 코드 복사(둘만, `Rules.net_encode/decode` = `TR1-` + base64(압축 JSON)). 채널 ctl(확실: hello·roster·me·go·fin·bye·left), st(빠름: 위치 `s`). 메시지의 `from`은 보낸 pid. 방장이 컴퓨터를 몰고 `host_order` 순서로 보내며, 받는 쪽 카트는 `remote` = 보간만. 나간 사람은 `gone`. 온라인에서는 멈춤이 게임을 멈추지 않는다. 코드 상자(`scripts/code_box.gd`)는 웹에서 진짜 HTML textarea. 웹에서만 된다(PC판은 WebRTC 확장 없음).
- CI(`ci.yml`): 소리 재생성 확인 → 테스트 → 켜지는지 → 경주가 도는지(`--dev=time`) → 웹 내보내기 → Pages 배포.
- 게임을 크게 바꾸면 조직 첫 화면(mhyoo-games.github.io `games.json`)과 이력서 저장소(minhyuk94.github.io)의 `games` 카드도 ko/ja/en으로 맞춘다. 소스 코드·저장소 링크는 이력서에 넣지 않는다.

## 이 작업 환경에서 돌려 보기

- npm/pip 설치와 github.io 접속이 막혀 있을 수 있다. Godot 실행 파일·웹 템플릿·글꼴은 dalmaru 저장소의 `godot-bin` 브랜치에서 꺼낸다 (`/opt/godot`에 풀어 둠).
- 테스트: `godot --headless --import` 후 `godot --headless -s tests/run_tests.gd`
- 화면 확인: `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --audio-driver Dummy -- --dev=<장면> --out=/tmp/x [--track=<id>]` (`scripts/dev.gd`, 장면: title, tracks, garage, help, race, duo, time, results). 경주 장면은 사람 카트도 컴퓨터가 몬다.
- 웹 확인: `godot --headless --export-release "Web" build/web/index.html` 후 로컬 http 서버 + Playwright(`/opt/npm-tools`) + `/usr/bin/google-chrome` (`--use-angle=swiftshader`).
- 온라인 확인: 같은 브라우저에서 페이지 두 개(context 둘)를 열어 확인한다(외부 STUN 없이도 같은 기계라 됨). 이 환경에서는 ntfy.sh에 못 닿으므로 작은 흉내 중계(POST /주제 저장, GET /주제/json → 줄마다 JSON, GET /주제/sse → SSE, CORS 허용)를 띄우고 주소에 `?relay=http://127.0.0.1:8770/`을 붙인다. 뒤에 있는 페이지는 브라우저가 멈추므로 `bringToFront()`로 번갈아 앞으로. 3D 여러 개라 매우 느리다(셋이면 screenshot timeout을 길게).
