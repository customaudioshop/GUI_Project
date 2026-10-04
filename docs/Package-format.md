# GUI 패키지 형식 (v0.2 초안)

GUI Builder가 만들고 GUI Player가 실행하는 파일 형식입니다. 화면 크기, 페이지, 위젯, 장치 연결, 위젯 동작(GuiScript)을 모두 담습니다.

- 위젯은 **칸(셀) 그리드 위의 블록**입니다. LEGO처럼 1×1, 2×1, 1×3, 2×2 … 크기의 블록을 원하는 칸에 빈틈 없이 놓습니다(5.2). 픽셀 좌표는 저장하지 않습니다.
- 모양은 **테마**(패키지 전체)와 위젯별 스타일로 정합니다(5.6). 같은 블록 구성으로 고객마다 다른 디자인을 만듭니다.

- 패키지에는 실행 코드가 없습니다. 레이아웃은 JSON이고 동작은 GuiScript 텍스트입니다([GuiScript 명세](GuiScript-spec.md)).
- Builder의 미리보기와 Player는 같은 렌더러(`shared/`)로 이 형식을 그립니다. 그래서 Builder에서 보이는 화면이 Player 화면과 같습니다.
- Player는 불러올 때 JSON 구조와 모든 스크립트를 다시 검증합니다. 오류가 있는 위젯의 스크립트는 실행하지 않습니다.

## 1. 파일 구성

확장자는 `.guipkg`이고 내용은 zip입니다.

```
my_mixer.guipkg
├── package.json        # 이 문서에서 정의하는 내용 전부
└── assets/
    ├── images/knob.png
    └── fonts/NanumGothic.ttf
```

- 에셋은 `package.json` 안에서 `assets/...` 상대 경로로 가리킵니다.
- 패키지 밖의 경로(절대 경로, `..`)는 허용하지 않습니다.

## 2. 최상위 구조

```json
{
  "format": "guipkg",
  "formatVersion": 2,
  "meta":    { "name": "Studio A Mixer", "author": "Jimmy", "created": "2026-10-04T10:00:00Z" },
  "theme":   { ... },
  "styles":  { ... },
  "devices": { ... },
  "layouts": [ ... ]
}
```

| 키 | 설명 |
|---|---|
| `format` | 항상 `"guipkg"` |
| `formatVersion` | 정수. 현재 `2`. Player가 아는 버전보다 크면 열지 않고 "Player를 업데이트하세요"라고 안내합니다. `1`(픽셀 좌표)은 불러올 때 칸으로 바꿉니다(5.8). |
| `meta` | 이름, 만든 사람, 만든 시각. 동작에는 영향이 없습니다. |
| `theme` | 패키지 전체의 모양 (5.6). 비어 있으면 기본 테마입니다. |
| `styles` | 이름 붙인 스타일 (5.6). 위젯의 `class`로 가리킵니다. |
| `devices` | 장치 연결 (4장). 모든 레이아웃이 공유합니다. |
| `layouts` | 화면 종류별 레이아웃 (3장). 각각 `screen`, `grid`, `pages`(5장)를 가집니다. |

## 3. 레이아웃과 화면

### 3.1 레이아웃 여러 개 (태블릿, 스마트폰, 폴더블)

화면 크기와 모양이 크게 다른 기기를 한 패키지로 지원합니다. 특히 폴더블은 **실행 중에 화면 모양이 바뀝니다**. 접으면 길쭉하고(약 21:9), 펴면 거의 정사각형(약 6:5)입니다. 레이아웃 하나로는 두 화면에 모두 맞출 수 없으므로, 화면마다 레이아웃을 따로 둡니다.

```json
"layouts": [
  { "id": "layout1", "name": "Tablet",        "screen": { "width": 1280, "height": 800, ... }, "grid": { "cols": 12, "rows": 8 }, "pages": [ ... ] },
  { "id": "layout2", "name": "Phone",         "screen": { "width": 393,  "height": 852, ... }, "grid": { "cols": 4,  "rows": 8 }, "pages": [ ... ] },
  { "id": "layout3", "name": "Fold unfolded", "screen": { "width": 690,  "height": 829, ... }, "grid": { "cols": 6,  "rows": 7 }, "pages": [ ... ] }
]
```

| 규칙 | 설명 |
|---|---|
| 같은 ID = 같은 컨트롤 | 레이아웃이 달라도 위젯 ID가 같으면 같은 컨트롤입니다. 값, 수신 규칙, 스크립트가 이어집니다. |
| 새 레이아웃 | Builder의 "+ Layout"은 현재 레이아웃을 새 화면 크기로 복사합니다. 블록은 같은 칸에 있고 칸 크기만 화면에 맞게 바뀝니다. 그다음 칸 개수와 배치를 다듬습니다(폰에서는 칸 수를 줄이고 블록을 다시 쌓거나 페이지를 나누는 식). 블록을 새 칸 수에 맞게 자동으로 다시 쌓는 기능(reflow)은 예정입니다. |
| 페이지 | 페이지 ID는 모든 레이아웃에 똑같이 있어야 합니다. `page "scene2"`가 어느 레이아웃에서든 동작해야 하기 때문입니다. Builder의 "+ Page"는 모든 레이아웃에 페이지를 추가합니다. |
| 레이아웃 선택 | Player는 **현재 화면 비율에 가장 가까운** 레이아웃을 고릅니다(비율의 로그 차이로 비교). 창 크기가 바뀌면(폴더블 접기/펴기, 회전) 다시 고릅니다. 바뀔 때 현재 페이지와 위젯 값은 유지됩니다. |
| 화면 방향 | 레이아웃이 모두 같은 방향이면 Player는 그 방향으로 화면을 고정합니다. 가로와 세로 레이아웃이 모두 있으면 기기 회전을 따라갑니다. |

**Builder 해상도 프리셋** (논리 단위 dp/pt. Mac은 기본 "보기 해상도", 폴더블은 Galaxy Z Fold/Flip급 기준 근사치)

새 패키지의 기본 목표 해상도는 **FHD 1920×1080 (가로)** 입니다.

| 종류 | 크기 |
|---|---|
| PC | **FHD 1920×1080 (기본)**, QHD 2560×1440, 4K UHD 3840×2160, WUXGA 1920×1200 |
| Mac | MacBook Air 13 1470×956, Air 15 1710×1112, Pro 14 1512×982, Pro 16 1728×1117, iMac 24 2240×1260 |
| 태블릿 | 1280×800, 1920×1200, iPad 1024×768, 2048×1536 |
| 스마트폰 | 360×800, 412×915, iPhone 393×852, iPhone Max 430×932 |
| 폴더블 | 접힘(커버) 344×882, 펼침(안쪽) 690×829, 플립 펼침 411×1006 |

**나중에 다룰 것**: 노치, 둥근 모서리, 폴더블 접힘선(hinge)을 피하는 안전 영역 처리. 작은 화면에서 너무 작은 위젯 경고(손가락 크기 기준). 한 레이아웃에서 복제나 그룹을 바꿨을 때 다른 레이아웃에 반영하는 도구.

### 3.2 화면: 기준 해상도 + 맞춤 규칙

각 레이아웃의 `screen`입니다.

```json
"screen": {
  "width": 1280,
  "height": 800,
  "orientation": "landscape",
  "fit": "keep",
  "background": "#1E1E1E"
}
```

| 키 | 값 | 설명 |
|---|---|---|
| `width`, `height` | 정수 (320~7680) | **기준 해상도** (논리 픽셀). 칸 크기는 이 크기와 `grid`에서 계산합니다(5.2). |
| `orientation` | `landscape` \| `portrait` | 이 레이아웃의 화면 방향 (3.1의 화면 방향 규칙) |
| `fit` | `keep` \| `expand` | 실제 기기 비율이 다를 때의 처리 (아래) |
| `background` | 색 | 여백과 페이지 배경 기본색 |

**`fit` 규칙**
- `keep` (기본): 비율을 유지한 채 화면에 꽉 차게 확대/축소합니다. 남는 영역은 `background` 색으로 채웁니다. 위젯 배치가 절대 바뀌지 않습니다.
- `expand`: 확대/축소는 같지만 남는 영역까지 페이지로 씁니다. 위젯의 `anchor`(5.2)에 따라 가장자리 위젯이 늘어난 영역 쪽으로 붙습니다. 비율이 크게 다른 기기도 지원해야 할 때 씁니다.

Godot에서는 `stretch_mode = canvas_items`, `stretch_aspect = keep` / `expand`에 해당합니다.

**Builder에서 기준 해상도를 바꾸면** 블록은 같은 칸에 그대로 있고 칸 크기만 다시 계산됩니다. 그래서 배치가 깨지지 않습니다. 글자 크기는 가로·세로 비율 중 작은 쪽으로 조정합니다. 이 작업은 실행 취소할 수 있습니다.

**기기 미리보기**: Builder는 자주 쓰는 기기 비율로 `fit` 결과를 미리 보여줍니다(예정).

## 4. 장치

GuiScript에서 쓰는 장치 이름(`mixer1`, `light1` …)을 여기서 정의합니다. 위젯은 이름만 쓰므로, 현장에서 IP가 바뀌어도 여기 한 곳만 고치면 됩니다.

```json
"devices": {
  "mixer1": { "protocol": "tcp",    "host": "192.168.0.10", "port": 5000 },
  "light1": { "protocol": "artnet", "host": "192.168.0.50", "universe": 0 },
  "synth":  { "protocol": "midi",   "port": "IAC Bus 1" },
  "relay":  { "protocol": "gpio",   "chip": "gpiochip0" }
}
```

- 장치 이름 규칙: 영문으로 시작, 영문/숫자/`_`, 최대 32자.
- `protocol` 값은 GuiScript의 `Protocols`와 같습니다: `tcp`, `udp`, `serial`, `artnet`, `sacn`, `dmx-usb`, `midi`, `gpio`, `ir`.
- 프로토콜별 설정 키(`host`, `port`, `baud` …)는 장치 드라이버를 구현할 때 확정합니다.
- 현장마다 달라지는 값(IP 등)은 Player 설정 화면에서 바꿀 수 있게 할 예정입니다(미정).

### 4.1 장치 프로필 (예정)

표준 위젯(5.3)이 장치를 알아서 제어하게 하는 데이터입니다. 개발자가 만들어 Player에 넣습니다. 사용자는 C#도 GuiScript도 쓰지 않고 장치만 고릅니다.

```json
"devices": {
  "proj_left": { "protocol": "tcp", "host": "192.168.0.21", "port": 4352, "profile": "pjlink" }
}
```

- 프로필은 기능 이름(예: 프로젝터의 `power.on`, `shutter.close`, `input.select`)마다 보낼 명령과, 받은 메시지를 상태로 바꾸는 규칙을 담습니다. 예: PJLink, 제조사별 RS-232 명령표.
- 프로젝터 위젯을 `proj_left`에 연결하면 전원/셔터/입력 버튼의 명령과 상태 표시가 프로필에서 채워집니다.
- 프로필이 없는 장치는 지금처럼 위젯의 `on`(GuiScript)과 `receive` 규칙을 직접 적습니다.
- 프로필도 실행 코드가 아니라 데이터입니다. iOS에서 내려받은 실행 코드를 쓸 수 없다는 제약을 지킵니다.
- 프로필 형식과 기본 제공 목록은 표준 위젯을 만들 때 확정합니다.

## 5. 페이지와 위젯

각 레이아웃의 `pages`입니다.

```json
"pages": [
  {
    "id": "main",
    "name": "메인",
    "widgets": [ ... ]
  }
]
```

- 페이지 `id`는 GuiScript의 `page "main"`에서 씁니다.
- `background`(선택): 이 페이지만의 배경색. 없으면 테마의 `background`를 씁니다.
- `widgets` 배열 순서가 그리기 순서입니다. 블록은 겹치지 않으므로 순서는 거의 상관없습니다.

### 5.1 위젯 공통 속성

```json
{
  "id": "ch1_fader",
  "type": "fader",
  "col": 2, "row": 0, "cw": 1, "ch": 3,
  "anchor": "top-left",
  "visible": true,
  "enabled": true,
  "class": "danger",
  "style": { ... },
  "value": { "min": 0, "max": 1, "step": 0, "default": 0 },
  "motion": { ... },
  "on": { "change": "send mixer1 \"SET CH1 VOL $value\\n\"" },
  "receive": [ ... ]
}
```

| 키 | 설명 |
|---|---|
| `id` | **패키지 전체에서 고유**. 수신 규칙과 스크립트가 위젯을 가리킬 때 씁니다. 장치 이름과 같은 규칙. |
| `type` | 위젯 종류 (5.3) |
| `col, row` | 블록의 왼쪽 위 칸 (0부터). 바깥 그리드(페이지, 패널, 그룹) 기준입니다. |
| `cw, ch` | 블록 크기 (칸 수, 1 이상) |
| `anchor` | `fit: expand`일 때 붙을 가장자리. `top-left`(기본), `top-right`, `bottom-left`, `bottom-right`, `center` 등 |
| `class` | (선택) `styles`에 정의한 스타일 이름 (5.6) |
| `style` | 이 위젯만의 색, 글꼴, 이미지 등 (5.6) |
| `value` | 위젯 값 (5.4) |
| `motion` | 페이더/엔코더를 움직일 때의 동작 (5.5) |
| `on` | 이벤트별 GuiScript (6장) |
| `receive` | 장치에서 받은 메시지로 값을 바꾸는 규칙 (7장) |

### 5.2 칸 그리드 (LEGO 블록)

화면을 칸으로 나누고, 위젯은 칸 단위 크기를 가진 블록으로 놓습니다. 테트리스는 비유일 뿐이고 블록이 저절로 떨어지지는 않습니다. 사용자가 원하는 칸에 놓되, **블록끼리 겹치거나 그리드 밖으로 나갈 수 없습니다**.

**레이아웃 그리드**

```json
"grid": { "cols": 12, "rows": 8, "gap": 8, "padding": 16 }
```

| 키 | 설명 |
|---|---|
| `cols`, `rows` | 칸 개수. 새 레이아웃은 칸 하나가 약 120 논리 픽셀이 되게 정합니다(최소 4×4). 예: FHD 1920×1080 → 16×9 |
| `gap` | (선택) 칸 사이 간격(픽셀). 없으면 테마의 `gap` |
| `padding` | (선택) 화면 가장자리와 그리드 사이 여백(픽셀). 없으면 테마의 `padding` |

칸 크기는 계산합니다: `칸 너비 = (화면 너비 − 2 × padding − (cols − 1) × gap) / cols`. 블록의 픽셀 사각형은 `x = padding + col × (칸 너비 + gap)`, `너비 = cw × 칸 너비 + (cw − 1) × gap`입니다(높이도 같음). 그래서 해상도, 칸 수, 간격, 테마 중 무엇을 바꿔도 모든 블록이 일관되게 다시 배치됩니다.

**블록 안의 그리드 (중첩)**

패널과 그룹은 안에 자기 그리드를 가집니다. 안쪽 블록의 `col, row, cw, ch`는 그 그리드 기준입니다.

```json
"grid": { "cols": 2, "rows": 12, "gap": 4 }
```

- `grid`가 없으면 **차지한 칸 수와 같은 그리드**(`cw × ch`)에 바깥과 같은 `gap`을 씁니다. 그러면 안쪽 칸이 바깥 칸과 줄이 맞아서, 블록을 그룹으로 묶어도 화면이 그대로입니다.
- 칸을 더 잘게 나누면(예: 1칸 너비 그룹에 `cols: 2`) 얇은 레벨 미터처럼 한 칸보다 작은 요소도 놓을 수 있습니다.
- 패널은 제목 띠와 안쪽 여백(테마 `panel.titleHeight`, `panel.padding`)을 뺀 영역을 그리드로 나눕니다.

**크기 규칙**

| 놓는 곳 | 블록 크기 |
|---|---|
| 페이지, 패널 | 위젯 종류가 정한 크기 중 하나 (5.3의 "크기"). 예: 페이더 1×2 ~ 1×5, 2×1 ~ 4×1 |
| 그룹 (컴포넌트 안쪽) | 아무 크기 (1×1 이상) |

**Builder 동작**
- 끌어 놓을 때 들어갈 칸을 초록 고스트로 보여 줍니다. 놓은 자리에 공간이 없으면 가장 가까운 빈칸에 놓고, 빈칸이 전혀 없으면 놓을 수 없습니다.
- 옮기기와 크기 바꾸기는 칸 단위입니다. 겹치거나 밖으로 나가면 빨간 테두리로 표시하고, 손을 떼면 원래 자리로 돌아갑니다.
- 손으로 고친 파일이나 이전 형식에서 바꾼 파일에 겹친 블록이 있으면 빨간 테두리로 계속 표시합니다. Player는 그대로 그립니다.
- 회전은 지원하지 않습니다.

### 5.3 위젯 종류

위젯 종류는 개발자가 **위젯 레지스트리**(`shared/gui_core/gui_widget_types.gd`) 한 곳에 정의합니다. 항목마다 팔레트 분류, 기본 크기, 허용 크기, 이벤트, 인스펙터에 보일 속성, 새 위젯의 기본값을 적습니다. 새 위젯 종류를 추가하면 Builder의 팔레트와 인스펙터가 자동으로 따라옵니다.

**기본 요소 (현재)**

| `type` | 분류 | 기본 크기 | 크기 (페이지·패널) | 값 | 이벤트 | 설명 |
|---|---|---|---|---|---|---|
| `button` | Basic | 2×1 | 1×1, 2×1, 3×1, 1×2, 2×2 | 0/1 | `press`, `release`, `change` | `mode`: `momentary`(누르는 동안 1) \| `toggle`(누를 때마다 0↔1). 팔레트에 1×1과 2×1 두 가지가 있습니다. |
| `fader` | Basic | 1×3 | 1×2 ~ 1×5, 2×1 ~ 4×1 | min~max | `change`, `touch`, `release` | 직선 슬라이더. 긴 쪽 방향으로 움직입니다(세로 블록이면 세로 페이더). |
| `encoder` | Basic | 1×1 | 1×1, 2×2, 3×3 | min~max | `change`, `touch`, `release` | 1단 엔코더(팔레트 이름 "Encoder 1-layer"). 로터리 엔코더/노브. 끝이 있는 노브와 무한 회전 모두 (5.5) |
| `dual_encoder` | Basic | 2×2 | 1×1, 2×2, 3×3 | `outer`, `inner` 각각 min~max | 부분마다 `change`, `touch`, `release` | 2단 엔코더(팔레트 이름 "Encoder 2-layer"). 바깥 링과 안쪽 노브가 한 축에 있습니다(예: 바깥 = 주파수, 안쪽 = 게인). 아래 "여러 값을 가진 위젯" |
| `label` | Display | 2×1 | 아무 크기 | 텍스트 | — | 글자 표시. 수신으로 글자를 바꿀 수 있습니다. |
| `led` | Display | 1×1 | 아무 크기 | 0~1 | — | 상태 표시등. 값에 따라 밝기/색이 바뀝니다. |
| `image` | Display | 2×2 | 아무 크기 | — | `press` | 그림. 누르면 이벤트를 낼 수 있습니다. |
| `panel` | Structure | 4×3 | 아무 크기 | — | — | 제목 띠가 있는 상자. 안에 자기 그리드로 위젯을 담습니다(`title`, `children`, `grid`). |
| `group` | Structure | — | 아무 크기 | — | — | 컴포넌트. 위젯을 묶어 복제해서 씁니다 (5.7). 팔레트에는 없고 Group 명령으로 만듭니다. |

모든 위젯은 **값 하나**를 가집니다(`label`은 텍스트, `image`/`panel`/`group`은 없음). 보낼 때는 이 값이 GuiScript의 `$value`가 되고, 받을 때는 이 값이 바뀝니다. 예외는 아래의 "여러 값을 가진 위젯"이고, 이때도 **부분 하나에 값 하나**입니다.

**여러 값을 가진 위젯 (부분)**

2중 엔코더처럼 한 위젯에 조작부가 둘 이상이면, 부분(part)마다 값, 움직임, 스크립트, 수신 규칙을 따로 가집니다. 부분 이름은 레지스트리의 `parts`에 정합니다.

```json
{
  "id": "eq1", "type": "dual_encoder",
  "col": 0, "row": 0, "cw": 2, "ch": 2,
  "motion": { "drag": "vertical", "sensitivity": 1.0, "acceleration": true, "resetOnDoubleTap": true, "sendInterval": 20 },
  "style": { "color": "#3A7BD5", "innerColor": "#F5A623" },
  "outer": {
    "label": "Freq",
    "value": { "min": 20, "max": 20000, "step": 1, "default": 1000 },
    "motion": { "endless": false, "angleRange": 270 },
    "on": { "change": "send mixer1 \"EQ1 FREQ $value\\n\"" },
    "receive": [ { "device": "mixer1", "text": "EQ1 FREQ {n}" } ]
  },
  "inner": {
    "label": "Gain",
    "value": { "min": -15, "max": 15, "step": 0.5, "default": 0 },
    "motion": { "endless": false, "angleRange": 270 },
    "on": { "change": "send mixer1 \"EQ1 GAIN $value\\n\"" },
    "receive": [ { "device": "mixer1", "text": "EQ1 GAIN {n}" } ]
  }
}
```

| 키 | 설명 |
|---|---|
| `outer`, `inner` | 부분. 각각 `label`(이름), `value`, `motion`, `on`, `receive`를 가집니다. 스크립트의 `$value`는 그 부분의 값입니다. |
| `motion` (위젯) | 두 부분이 같이 쓰는 움직임(끌기 방향, 감도 등). 부분의 `motion`이 같은 키를 덮어씁니다(`endless`, `angleRange` 등). |
| `style.color`, `style.innerColor` | 바깥 링과 안쪽 노브 색. 기본값은 테마의 `primary`, `secondary` |

- **터치**: 안쪽 노브(반지름의 약 58%) 안을 누르면 안쪽, 그 바깥 링을 누르면 바깥 값이 바뀝니다. 그다음 끄는 동안에는 처음 고른 부분만 움직입니다. 두 번 탭하면 누른 부분만 기본값으로 돌아갑니다.
- **이벤트 이름**: 부분의 이벤트는 `위젯ID.부분`으로 구분합니다(`eq1.outer`, `eq1.inner`). 위젯 ID에는 `.`을 쓸 수 없으므로 헷갈리지 않습니다.
- 1×1 크기는 손가락으로 안쪽과 바깥을 구분하기 어려우므로 2×2 이상을 권장합니다.

**표준 위젯 (예정)**

장치 제어 현장에서 어디에나 있는 부품은 **기본 제공 위젯**으로 만듭니다. 사용자가 버튼을 조합해 만들 필요 없이 끌어다 놓으면 바로 동작합니다.

| 분야 | 표준 위젯 |
|---|---|
| 영상 | 프로젝터(전원, 셔터, 입력 선택), 디스플레이/TV, 전동 스크린(▲ ■ ▼), 매트릭스 스위처, 카메라 PTZ |
| 오디오 | 볼륨 페이더(레벨, 뮤트, 미터), 로터리 엔코더, 채널 스트립, EQ, 마이크 |
| 조명 | 디머, RGB/컬러, 씬 프리셋, DMX 채널 |
| 공통 | 선택 그룹(하나만 켜지는 버튼 묶음), 매크로/씬 버튼, 레벨 미터, 값 표시, 시계/타이머, 페이지 이동 |

표준 위젯은 **장치 프로필**과 연결합니다(4.1). 위젯에서 장치를 고르면 명령과 상태 피드백이 자동으로 채워집니다. 표준 위젯도 블록 크기를 가지며 테마를 따릅니다.

모든 위젯은 **값 하나**를 가집니다(`label`은 텍스트, `image`/`panel`은 없음). 보낼 때는 이 값이 GuiScript의 `$value`가 되고, 받을 때는 이 값이 바뀝니다.

### 5.4 값

```json
"value": { "min": 0, "max": 1, "step": 0, "default": 0 }
```

| 키 | 설명 |
|---|---|
| `min`, `max` | 값 범위. 기본 0~1. `min > max`로 쓰면 방향이 뒤집힙니다. |
| `step` | 0이면 연속값. 예: `step: 1`, `min: 0`, `max: 127`이면 MIDI 값처럼 정수만 나옵니다. |
| `default` | 처음 값. `motion.resetOnDoubleTap`이 켜져 있으면 두 번 탭할 때 이 값으로 돌아갑니다. |

### 5.5 움직임 (페이더/엔코더)

손가락으로 움직일 때 값이 어떻게 바뀌는지 정합니다.

**페이더**

```json
"motion": {
  "touchMode": "relative",
  "sensitivity": 1.0,
  "resetOnDoubleTap": true,
  "sendInterval": 20
}
```

| 키 | 설명 |
|---|---|
| `touchMode` | `jump`: 누른 위치로 값이 바로 이동. `relative`(기본): 누른 위치와 상관없이 끌어간 거리만큼 바뀜. 실수로 값이 튀는 것을 막아 공연/방송 현장에서 안전합니다. |
| `sensitivity` | `relative`에서 끌어간 거리 대비 변화량. 1.0이면 페이더 길이 = 전체 범위. |
| `resetOnDoubleTap` | 두 번 탭하면 `default` 값으로 |
| `sendInterval` | `change` 스크립트를 실행하는 최소 간격(ms, 0~1000). 손을 빠르게 움직여도 장치에 메시지가 몰리지 않게 합니다. 마지막 값은 항상 보냅니다. |

**엔코더**

```json
"motion": {
  "endless": false,
  "angleRange": 270,
  "drag": "vertical",
  "sensitivity": 1.0,
  "acceleration": true,
  "resetOnDoubleTap": true,
  "sendInterval": 20
}
```

| 키 | 설명 |
|---|---|
| `endless` | `false`: 끝이 있는 노브(min~max에서 멈춤). `true`: 무한 회전 엔코더. 값이 min/max를 넘으면 반대쪽으로 넘어가고, 스크립트에 변화량 `$delta`도 전달됩니다. |
| `angleRange` | 끝이 있는 노브가 그려지는 회전 각도(30~360). 기본 270°. |
| `drag` | `vertical`(기본): 위/아래로 끌기. `horizontal`: 좌/우로 끌기. `circular`: 노브를 따라 원을 그리며 돌리기. 작은 노브는 원을 그리기 어려워서 `vertical`이 기본입니다. |
| `sensitivity` | 1.0이면 200 논리 픽셀을 끌 때 전체 범위(무한 엔코더는 한 바퀴). |
| `acceleration` | 빠르게 돌리면 더 많이 바뀝니다. 넓은 범위를 빨리 움직일 때 편합니다. |
| `resetOnDoubleTap`, `sendInterval` | 페이더와 같음 |

### 5.6 모양: 테마, 스타일 이름, 위젯 스타일

고객마다 다른 디자인을 위해 모양을 세 단계로 정합니다. 위에서부터 먼저 찾은 값을 씁니다.

1. 위젯의 `style` (그 위젯 하나)
2. 위젯의 `class`가 가리키는 `styles`의 항목 (같은 이름을 붙인 위젯 전부)
3. 패키지의 `theme` (전체)

**테마**

```json
"theme": {
  "background": "#1E1E1E",
  "surface": "#2E3036",
  "primary": "#3A7BD5",
  "secondary": "#F5A623",
  "text": "#FFFFFF",
  "textDim": "#A0A4AC",
  "border": "#4A4D55",
  "ok": "#4CD964",
  "fontSize": 18,
  "radius": 6,
  "gap": 8,
  "padding": 16,
  "panel": {
    "background": "#1B2430", "border": "#3A7BD5", "borderWidth": 1, "radius": 4, "padding": 8,
    "titleHeight": 36, "titleBackground": "#1F5F8B", "titleColor": "#FFFFFF", "titleFontSize": 18
  }
}
```

| 키 | 쓰는 곳 |
|---|---|
| `background` | 페이지 배경 |
| `surface` | 꺼진 버튼 바탕, 노브 몸체, 페이더 트랙 |
| `primary` | 강조색: 켜진 버튼, 페이더 채움, 노브 호 |
| `secondary` | 두 번째 강조색: 2중 엔코더의 안쪽 노브 |
| `text`, `textDim` | 글자색 |
| `ok` | LED 색 |
| `fontSize`, `radius` | 기본 글자 크기, 모서리 둥글기 |
| `gap`, `padding` | 그리드의 기본 칸 간격과 바깥 여백 (5.2) |
| `panel.*` | 패널 바탕, 테두리, 안쪽 여백, 제목 띠 |

패키지에는 바꾼 키만 저장합니다. 빠진 키는 기본 테마 값입니다. 기본값은 `shared/gui_core/gui_theme.gd`에 있습니다.

**스타일 이름**

```json
"styles": {
  "danger": { "textColor": "#E53935" },
  "big":    { "fontSize": 28 }
}
```

위젯에 `"class": "danger"`라고 적으면 그 값을 씁니다. 예를 들어 빨간 ON 글자 버튼을 한 번에 바꿀 수 있습니다.

**위젯 스타일 키** (지금 렌더러가 쓰는 것)

| 키 | 위젯 | 테마 기본값 |
|---|---|---|
| `text` | button, label | — |
| `color` | button, fader, encoder, dual_encoder 바깥 (강조색), led (켜진 색) | `primary` (led는 `ok`) |
| `innerColor` | dual_encoder 안쪽 | `secondary` |
| `background` | button, fader, encoder, panel, group | `surface` (panel은 `panel.background`) |
| `textColor` | button, label | `text` |
| `fontSize` | button, label | `fontSize` |
| `radius` | button, panel | `radius` (panel은 `panel.radius`) |
| `borderColor`, `borderWidth` | panel | `panel.border`, `panel.borderWidth` |
| `image`, `font` | image, (예정) 이미지 스킨, 글꼴 | — |

상태별 모양(눌림, 선택됨, 비활성, 오프라인)과 이미지 스킨은 예정입니다.

### 5.7 그룹 (계층 구조)

믹서 채널처럼 같은 구성이 반복되는 화면을 위한 기능입니다. 페이더 1개, EQ 엔코더 3개, MUTE/AUX 버튼을 `ch1` 그룹으로 묶고 복제해서 `ch2`, `ch3` …을 만듭니다.

```json
{
  "id": "ch1", "type": "group",
  "col": 1, "row": 0, "cw": 1, "ch": 6,
  "grid": { "cols": 2, "rows": 12, "gap": 4 },
  "params": { "ch": 1 },
  "children": [
    { "id": "ch1_eq_hi", "type": "encoder", "col": 0, "row": 0, "cw": 2, "ch": 2 },
    { "id": "ch1_mute",  "type": "button",  "col": 0, "row": 6, "cw": 1, "ch": 1 },
    { "id": "ch1_aux",   "type": "button",  "col": 1, "row": 6, "cw": 1, "ch": 1 },
    { "id": "ch1_fader", "type": "fader",   "col": 0, "row": 7, "cw": 2, "ch": 5,
      "on": { "change": "set $level = round($value * 255)\nsend mixer1 \"SET CH$ch VOL $level\\n\"" } }
  ]
}
```

| 키 | 설명 |
|---|---|
| `children` | 그룹에 담긴 위젯. 칸은 **그룹의 그리드 기준**입니다(5.2). 그룹을 옮기면 함께 움직입니다. 그룹 안에 그룹을 넣을 수 있습니다. |
| `grid` | (선택) 그룹 안의 그리드. 없으면 그룹이 차지한 칸과 같은 그리드입니다. 그룹 안에서는 블록 크기 제한이 없습니다. |
| `params` | 그룹 변수. 그룹 안 모든 위젯의 스크립트에서 읽기 전용 변수(`$ch`)로 쓸 수 있습니다. 바깥 그룹의 변수도 보이며, 이름이 같으면 안쪽 그룹이 이깁니다. |
| `style.background` | (선택) 그룹 배경색. 없으면 그룹은 화면에 보이지 않습니다. |

**복제 규칙** (Builder의 Duplicate)
- ID 끝의 숫자를 다음 빈 번호로 바꿉니다. 안쪽 위젯 ID에 들어 있는 그룹 이름도 같이 바뀝니다: `ch1` → `ch2`, `ch1_fader` → `ch2_fader`.
- 그룹 이름이 들어 있지 않은 안쪽 ID(`encoder3` 등)는 새 빈 이름을 받습니다. 그래서 Builder는 그룹 위에 놓은 위젯에 `ch1_encoder1`처럼 그룹 이름을 앞에 붙입니다.
- `params`의 숫자는 번호가 바뀐 만큼 커집니다: `ch: 1` → `ch: 2`. 스크립트는 그대로 복사됩니다. 그래서 `$ch`를 쓰는 스크립트는 고치지 않아도 다음 채널을 제어합니다.
- 복제본은 원본 오른쪽에서 가장 가까운 빈칸에 놓입니다. 빈칸이 없으면 바로 오른쪽에 놓고 겹침을 빨간색으로 표시합니다.
- **Group**은 선택한 블록들이 차지한 칸을 감싸는 그룹을 만듭니다(같은 바깥 그리드에 있는 블록만). 이때 안쪽 위젯 ID 앞에 그룹 이름을 붙입니다(`button1` → `group1_button1`). 그래서 복제하면 세트 전체가 함께 번호를 올립니다(`group2`, `group2_button1`).
- **계층 창 드래그**: 줄 사이에 놓으면 순서가 바뀌고, 패널이나 그룹 위에 놓으면 그 안으로 들어갑니다. 밖으로 꺼낼 때도 같습니다. 새 그리드에서 원래 칸이 비어 있으면 그대로, 아니면 가장 가까운 빈칸에 놓습니다(빈칸이 없으면 옮기지 않고 알려 줍니다). 그룹이나 패널 안으로 들어가면 ID 앞에 그 이름이 붙습니다.
- 여러 블록 선택: 빈 곳에서 끌어 사각형을 그리면 닿는 블록이 모두 선택됩니다(Shift를 누르면 추가). Shift+클릭, Ctrl/Cmd+A(같은 그리드 전체)도 됩니다. **Ungroup**은 그룹을 풀어 안쪽 블록을 바깥 그리드의 같은 자리에 놓습니다.

### 5.8 이전 형식(픽셀) 바꾸기

`formatVersion: 1` 파일은 위젯을 픽셀(`x, y, w, h`)로 놓았습니다. 불러올 때 레이아웃마다 칸 하나가 약 120 픽셀인 그리드(간격·여백 0)를 만들고, 각 위젯을 가장 가까운 칸으로 바꿉니다. 반올림 때문에 겹친 블록은 Builder가 빨간색으로 보여 주므로 손으로 정리합니다. 저장하면 `formatVersion: 2`가 됩니다.

## 6. 보내기: 이벤트 → GuiScript

```json
"on": {
  "change":  "set $level = round(scale($value, 0, 1, 0, 255))\ndmx light1 1 ($level)",
  "release": "log \"fader released\""
}
```

- 키는 5.3의 이벤트 이름, 값은 GuiScript 텍스트입니다.
- 스크립트가 받는 읽기 전용 변수:

| 변수 | 타입 | 제공하는 위젯 |
|---|---|---|
| `$value` | 숫자 (label은 텍스트) | 값이 있는 모든 위젯. 부분이 있는 위젯은 그 부분의 값 |
| `$delta` | 숫자 | `encoder` (`endless: true`) |
| `$<param>` | 숫자 | 그룹 안의 위젯 (5.7의 `params`) |

이 변수들은 GuiScript 검증 시 `ValidationContext.ContextVariables`로 넘깁니다. 장치와 페이지 목록도 패키지에서 채워 넘깁니다.

## 7. 받기: 장치 메시지 → 위젯 값

받는 쪽은 스크립트가 아니라 **규칙**으로 정합니다. "이 장치에서 이런 메시지가 오면 이 위젯 값을 이렇게 바꾼다"만 적습니다.

```json
"receive": [
  { "device": "mixer1", "text":  "CH1 VOL {n}",              "value": "$n / 255" },
  { "device": "synth",  "midi":  { "type": "cc", "channel": 1, "number": 7 }, "value": "$n / 127" }
]
```

| 키 | 설명 |
|---|---|
| `device` | 장치 이름 |
| `text` | (`tcp`, `udp`, `serial`) 한 줄 메시지 형식. `{이름}` 자리에 숫자나 글자가 오면 `$이름` 변수로 꺼냅니다. 나머지 글자는 정확히 같아야 합니다. |
| `midi` | (`midi`) `type`: `cc` \| `note` \| `pc`, `channel`, `number`. 받은 값은 `$n`입니다. |
| `value` | 새 위젯 값을 계산하는 GuiScript **식** 하나(명령 없음). 생략하면 꺼낸 값을 그대로 씁니다. 결과는 `min~max`로 잘립니다. |

규칙은 위에서부터 검사하고, 맞는 규칙이 여러 개면 모두 적용합니다. 다른 프로토콜(hex, DMX 입력 등)은 필요해질 때 추가합니다.

### 7.1 에코 방지 (필수 규칙)

1. **수신으로 값이 바뀌면 `change` 스크립트를 실행하지 않습니다.** 화면만 바뀝니다. 그렇지 않으면 앱 → 믹서 → 앱 → 믹서 … 로 메시지가 끝없이 오갑니다.
2. **사용자가 위젯을 만지는 동안 들어온 값은 무시합니다.** 손을 떼면 마지막으로 받은 값을 적용합니다. 손가락 아래에서 페이더가 튀는 것을 막습니다.

## 8. 전체 예시

```json
{
  "format": "guipkg",
  "formatVersion": 2,
  "meta": { "name": "Studio A", "author": "Jimmy", "created": "2026-10-04T10:00:00Z" },
  "theme": { "primary": "#22D3EE", "panel": { "titleBackground": "#0E4A6E" } },
  "styles": { "danger": { "textColor": "#E53935" } },
  "devices": {
    "mixer1": { "protocol": "tcp", "host": "192.168.0.10", "port": 5000 },
    "light1": { "protocol": "artnet", "host": "192.168.0.50", "universe": 0 }
  },
  "layouts": [
    {
      "id": "layout1", "name": "Tablet",
      "screen": { "width": 1280, "height": 800, "orientation": "landscape", "fit": "keep", "background": "#1E1E1E" },
      "grid": { "cols": 12, "rows": 8 },
      "pages": [
        {
          "id": "main",
          "name": "메인",
          "widgets": [
            {
              "id": "ch1_fader", "type": "fader",
              "col": 0, "row": 0, "cw": 1, "ch": 4,
              "value": { "min": 0, "max": 1, "step": 0, "default": 0.75 },
              "motion": { "touchMode": "relative", "sensitivity": 1.0, "resetOnDoubleTap": true, "sendInterval": 20 },
              "on": { "change": "set $level = round($value * 255)\nsend mixer1 \"SET CH1 VOL $level\\n\"" },
              "receive": [ { "device": "mixer1", "text": "CH1 VOL {n}", "value": "$n / 255" } ]
            },
            {
              "id": "ch1_mute", "type": "button", "mode": "toggle",
              "col": 0, "row": 4, "cw": 1, "ch": 1, "class": "danger",
              "style": { "text": "MUTE" },
              "on": { "change": "if $value > 0\n    send mixer1 \"MUTE CH1 ON\\n\"\nelse\n    send mixer1 \"MUTE CH1 OFF\\n\"\nend" },
              "receive": [ { "device": "mixer1", "text": "CH1 MUTE {n}" } ]
            },
            {
              "id": "dimmer", "type": "encoder",
              "col": 2, "row": 0, "cw": 2, "ch": 2,
              "value": { "min": 0, "max": 255, "step": 1, "default": 0 },
              "motion": { "endless": false, "angleRange": 270, "drag": "vertical", "sensitivity": 1.0, "acceleration": true },
              "on": { "change": "dmx light1 1 ($value)" }
            },
            {
              "id": "go_scene2", "type": "button", "mode": "momentary",
              "col": 10, "row": 7, "cw": 2, "ch": 1,
              "style": { "text": "Scene 2" },
              "on": { "press": "page \"scene2\"" }
            },
            {
              "id": "screen", "type": "panel", "title": "전체 스크린",
              "col": 5, "row": 0, "cw": 2, "ch": 4,
              "grid": { "cols": 1, "rows": 3 },
              "children": [
                { "id": "screen_up",   "type": "button", "col": 0, "row": 0, "cw": 1, "ch": 1, "style": { "text": "▲" } },
                { "id": "screen_stop", "type": "button", "col": 0, "row": 1, "cw": 1, "ch": 1, "style": { "text": "■" } },
                { "id": "screen_down", "type": "button", "col": 0, "row": 2, "cw": 1, "ch": 1, "style": { "text": "▼" } }
              ]
            }
          ]
        },
        { "id": "scene2", "name": "장면 2", "widgets": [] }
      ]
    }
  ]
}
```

## 9. 정해지지 않은 것

- 패키지를 Player로 보내는 방법 (로컬 파일 / 서버 / 앱에 포함)
- 프로토콜별 장치 설정 키
- 현장에서 장치 주소를 바꾸는 Player 설정 화면
- 상태별 모양(눌림, 선택됨, 비활성, 오프라인)과 이미지 스킨
- 칸 수가 다른 레이아웃으로 블록을 자동으로 다시 쌓는 규칙(reflow)
- 장치 프로필 형식과 표준 위젯 목록 (4.1, 5.3)
- 사용자 컴포넌트 라이브러리와 페이지 템플릿 저장 형식
- 레이아웃 사이에서 구조 변경(복제, 그룹)을 맞춰 주는 도구
- 위젯 여러 개를 한 번에 바꾸는 스크립트 명령 (예: `set.widget ch1_fader 0.5`)이 필요한지
