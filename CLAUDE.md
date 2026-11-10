# 이 저장소에서 작업할 때 지킬 것

유민혁(minhyuk94)의 개인 프로젝트 "토이 레이싱". 사용자는 한국어로 대화합니다. 게임 글자도 한국어.

## 무엇인가

숲속 장난감 카트 3D 레이싱 (경주·혼자 연습·둘이서 화면 나누기, 카트 상점, 트랙 3개). Godot 4.6(GDScript, GL Compatibility), 웹으로 내보내 GitHub Pages(`https://mhyoo-games.github.io/toy_racing/`, 조직 mhyoo-games)에 올린다.

## 지킬 것

- 옛 온라인 카트 레이싱에서 영감을 받았지만 **새로 만든 게임**이다. 다른 게임의 이름·캐릭터·카트·트랙·그림·음악을 쓰지 않고, 다른 회사·게임 이름을 README·화면·이력서에 넣지 않는다.
- 그림: Kenney Mini Forest(CC0, `assets/forest/LICENSE.txt`)를 트랙 꾸밈·운전수(`character-archer.glb`의 `drive` 동작)로 쓰고, 카트·도로·연석·출발 문은 코드로 만든다(`scripts/kart.gd`, `scripts/track_view.gd`). 글꼴: 갈무리(OFL).
- 소리: `tools/sound/gen.py`가 표준 라이브러리로 합성 → `assets/sfx`, `assets/music`. 결과 wav를 직접 고치지 말고 생성기를 고친다. 아이콘은 `tools/art/icon.py`.
- 규칙(계산)은 `scripts/rules.gd`에 화면과 떨어뜨려 모은다: 카트 물리(좌표 `Vector2(x, z)`, yaw 0 = +z, 오른쪽 핸들 = yaw 감소), 드리프트(미끄러짐 각을 유지하며 길이 굽음, 카운터로 끝), 게이지·부스터(두 개까지), 순간부스터(드리프트 끝난 뒤 `MINI_WINDOW` 안에 가속 다시 누르기), 출발 부스터, 잔디 감속(부스터면 덜 느림 = 커팅), 울타리, 랩·순위, 레이싱 라인, 컴퓨터 입력, 보상·상점·저장. 새 규칙에는 `tests/run_tests.gd`에 테스트를 더한다.
- 트랙은 `data/tracks.json`(조절점·폭). 트랙을 바꾸면 테스트(컴퓨터가 3바퀴를 벽에 거의 안 박고 도는지, 출발 자리가 도로 위인지)가 통과해야 한다. 카트는 `data/karts.json`(능력치 1~10, 값 순서).
- 컴퓨터 상대는 사람 카트의 능력치를 기준으로 달린다(`Rules.ai_stats`) — 카트 종류는 겉모양만. 너무 어렵지 않게.
- 저장은 `user://toy_racing_save.json` 하나 (`Rules.parse_save`가 망가진 값도 받아 준다).
- Godot 4.6은 Variant에서 `:=`로 타입을 추론하면 오류다. 딕셔너리 값은 `var x: float = d.y`처럼 타입을 적는다. `Node`의 `tr()`과 이름이 겹치므로 트랙 변수는 `trk`.
- CanvasLayer 아래 Control은 창의 theme을 못 물려받는다 → 기본 글꼴은 `project.godot`의 `gui/theme/custom_font`(갈무리)로. 오른쪽 붙이기는 `set_anchors_preset` 뒤 offset을 직접 준다.
- CI(`ci.yml`): 소리 재생성 확인 → 테스트 → 켜지는지 → 경주가 도는지(`--dev=time`) → 웹 내보내기 → Pages 배포.
- 게임을 크게 바꾸면 조직 첫 화면(mhyoo-games.github.io `games.json`)과 이력서 저장소(minhyuk94.github.io)의 `games` 카드도 ko/ja/en으로 맞춘다. 소스 코드·저장소 링크는 이력서에 넣지 않는다.

## 이 작업 환경에서 돌려 보기

- npm/pip 설치와 github.io 접속이 막혀 있을 수 있다. Godot 실행 파일·웹 템플릿·글꼴은 dalmaru 저장소의 `godot-bin` 브랜치에서 꺼낸다 (`/opt/godot`에 풀어 둠).
- 테스트: `godot --headless --import` 후 `godot --headless -s tests/run_tests.gd`
- 화면 확인: `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --audio-driver Dummy -- --dev=<장면> --out=/tmp/x [--track=<id>]` (`scripts/dev.gd`, 장면: title, tracks, garage, help, race, duo, time, results). 경주 장면은 사람 카트도 컴퓨터가 몬다.
- 웹 확인: `godot --headless --export-release "Web" build/web/index.html` 후 로컬 http 서버 + Playwright(`/opt/npm-tools`) + `/usr/bin/google-chrome` (`--use-angle=swiftshader`).
