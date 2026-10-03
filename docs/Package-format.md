# GUI 패키지 형식 (v0.1 초안)

GUI Builder가 만들고 GUI Player가 실행하는 파일 형식입니다. 화면 크기, 페이지, 위젯, 장치 연결, 위젯 동작(GuiScript)을 모두 담습니다.

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
  "formatVersion": 1,
  "meta":    { "name": "Studio A Mixer", "author": "Jimmy", "created": "2026-10-04T10:00:00Z" },
  "devices": { ... },
  "layouts": [ ... ],
  "editor":  { ... }
}
```

| 키 | 설명 |
|---|---|
| `format` | 항상 `"guipkg"` |
| `formatVersion` | 정수. Player가 아는 버전보다 크면 열지 않고 "Player를 업데이트하세요"라고 안내합니다. |
| `meta` | 이름, 만든 사람, 만든 시각. 동작에는 영향이 없습니다. |
| `devices` | 장치 연결 (4장). 모든 레이아웃이 공유합니다. |
| `layouts` | 화면 종류별 레이아웃 (3장). 각각 `screen`과 `pages`(5장)를 가집니다. |
| `editor` | Builder 전용 설정(그리드 크기, 스냅 등). Player는 무시합니다. |

## 3. 레이아웃과 화면

### 3.1 레이아웃 여러 개 (태블릿, 스마트폰, 폴더블)

화면 크기와 모양이 크게 다른 기기를 한 패키지로 지원합니다. 특히 폴더블은 **실행 중에 화면 모양이 바뀝니다**. 접으면 길쭉하고(약 21:9), 펴면 거의 정사각형(약 6:5)입니다. 레이아웃 하나로는 두 화면에 모두 맞출 수 없으므로, 화면마다 레이아웃을 따로 둡니다.

```json
"layouts": [
  { "id": "layout1", "name": "Tablet",        "screen": { "width": 1280, "height": 800, ... }, "pages": [ ... ] },
  { "id": "layout2", "name": "Phone",         "screen": { "width": 393,  "height": 852, ... }, "pages": [ ... ] },
  { "id": "layout3", "name": "Fold unfolded", "screen": { "width": 690,  "height": 829, ... }, "pages": [ ... ] }
]
```

| 규칙 | 설명 |
|---|---|
| 같은 ID = 같은 컨트롤 | 레이아웃이 달라도 위젯 ID가 같으면 같은 컨트롤입니다. 값, 수신 규칙, 스크립트가 이어집니다. |
| 새 레이아웃 | Builder의 "+ Layout"은 현재 레이아웃을 새 화면 크기로 비율대로 줄이거나 늘려 복사합니다. 그다음 배치를 다듬습니다(폰에서는 채널 수를 줄이거나 페이지를 나누는 식). |
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
| `width`, `height` | 정수 (320~7680) | **기준 해상도**. 모든 위젯 좌표는 이 크기 안의 논리 픽셀입니다. |
| `orientation` | `landscape` \| `portrait` | 이 레이아웃의 화면 방향 (3.1의 화면 방향 규칙) |
| `fit` | `keep` \| `expand` | 실제 기기 비율이 다를 때의 처리 (아래) |
| `background` | 색 | 여백과 페이지 배경 기본색 |

**`fit` 규칙**
- `keep` (기본): 비율을 유지한 채 화면에 꽉 차게 확대/축소합니다. 남는 영역은 `background` 색으로 채웁니다. 위젯 배치가 절대 바뀌지 않습니다.
- `expand`: 확대/축소는 같지만 남는 영역까지 페이지로 씁니다. 위젯의 `anchor`(5.2)에 따라 가장자리 위젯이 늘어난 영역 쪽으로 붙습니다. 비율이 크게 다른 기기도 지원해야 할 때 씁니다.

Godot에서는 `stretch_mode = canvas_items`, `stretch_aspect = keep` / `expand`에 해당합니다.

**Builder에서 기준 해상도를 바꾸면** 그 레이아웃의 모든 위젯의 `x, y, w, h`를 가로·세로 비율대로 다시 계산합니다. 글자 크기는 두 비율 중 작은 쪽으로 조정합니다. 이 작업은 실행 취소할 수 있습니다.

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

## 5. 페이지와 위젯

각 레이아웃의 `pages`입니다.

```json
"pages": [
  {
    "id": "main",
    "name": "메인",
    "background": "#202020",
    "widgets": [ ... ]
  }
]
```

- 페이지 `id`는 GuiScript의 `page "main"`에서 씁니다.
- `widgets` 배열 순서가 그리기 순서입니다. 뒤에 있을수록 위에 그려집니다.

### 5.1 위젯 공통 속성

```json
{
  "id": "ch1_fader",
  "type": "fader",
  "x": 100, "y": 80, "w": 60, "h": 400,
  "anchor": "top-left",
  "visible": true,
  "enabled": true,
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
| `x, y, w, h` | 기준 해상도 안의 논리 픽셀. 원점은 왼쪽 위. |
| `anchor` | `fit: expand`일 때 붙을 가장자리. `top-left`(기본), `top-right`, `bottom-left`, `bottom-right`, `center` 등 |
| `style` | 색, 글꼴, 이미지 등 모양 (5.6) |
| `value` | 위젯 값 (5.4) |
| `motion` | 페이더/엔코더를 움직일 때의 동작 (5.5) |
| `on` | 이벤트별 GuiScript (6장) |
| `receive` | 장치에서 받은 메시지로 값을 바꾸는 규칙 (7장) |

### 5.2 좌표와 크기 제한

- `w`, `h`는 최소 16 논리 픽셀입니다.
- 위젯이 기준 해상도 밖으로 일부 나가도 저장은 되지만 Builder가 경고합니다.
- 회전은 v1에서 지원하지 않습니다.

### 5.3 위젯 종류 (v1)

| `type` | 값 | 이벤트 | 설명 |
|---|---|---|---|
| `button` | 0/1 | `press`, `release`, `change` | `mode`: `momentary`(누르는 동안 1) \| `toggle`(누를 때마다 0↔1) |
| `fader` | min~max | `change`, `touch`, `release` | 직선 슬라이더. `orientation`: `vertical` \| `horizontal` |
| `encoder` | min~max | `change`, `touch`, `release` | 회전 노브. 끝이 있는 노브와 무한 회전 엔코더 모두 (5.5) |
| `label` | 텍스트 | — | 글자 표시. 수신으로 글자를 바꿀 수 있습니다. |
| `led` | 0~1 | — | 상태 표시등. 값에 따라 밝기/색이 바뀝니다. |
| `image` | — | `press` | 그림. 누르면 이벤트를 낼 수 있습니다. |
| `panel` | — | — | 배경 상자. 모양만 있고 다른 위젯을 담지는 않습니다. |
| `group` | — | — | 다른 위젯을 담는 묶음. 채널 스트립처럼 복제해서 씁니다 (5.7) |

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

### 5.6 모양

```json
"style": {
  "color": "#3A7BD5",
  "background": "#2B2B2B",
  "text": "CH 1",
  "font": "assets/fonts/NanumGothic.ttf",
  "fontSize": 18,
  "image": "assets/images/knob.png"
}
```

위젯 종류마다 쓰는 키가 다릅니다. 정확한 목록은 렌더러를 만들면서 확정합니다. 없는 키는 테마 기본값을 씁니다.

### 5.7 그룹 (계층 구조)

믹서 채널처럼 같은 구성이 반복되는 화면을 위한 기능입니다. 페이더 1개, EQ 엔코더 3개, MUTE/AUX 버튼을 `ch1` 그룹으로 묶고 복제해서 `ch2`, `ch3` …을 만듭니다.

```json
{
  "id": "ch1", "type": "group",
  "x": 40, "y": 60, "w": 120, "h": 640,
  "params": { "ch": 1 },
  "children": [
    { "id": "ch1_fader", "type": "fader", "x": 30, "y": 300, "w": 60, "h": 300,
      "on": { "change": "set $level = round($value * 255)\nsend mixer1 \"SET CH$ch VOL $level\\n\"" } },
    { "id": "ch1_eq_hi", "type": "encoder", "x": 20, "y": 0, "w": 80, "h": 80 },
    { "id": "ch1_mute", "type": "button", "x": 20, "y": 240, "w": 80, "h": 40 }
  ]
}
```

| 키 | 설명 |
|---|---|
| `children` | 그룹에 담긴 위젯. 좌표는 **그룹 기준**입니다. 그룹을 옮기면 함께 움직입니다. 그룹 안에 그룹을 넣을 수 있습니다. |
| `params` | 그룹 변수. 그룹 안 모든 위젯의 스크립트에서 읽기 전용 변수(`$ch`)로 쓸 수 있습니다. 바깥 그룹의 변수도 보이며, 이름이 같으면 안쪽 그룹이 이깁니다. |
| `style.background` | (선택) 그룹 배경색. 없으면 그룹은 화면에 보이지 않습니다. |

**복제 규칙** (Builder의 Duplicate)
- ID 끝의 숫자를 다음 빈 번호로 바꿉니다. 안쪽 위젯 ID에 들어 있는 그룹 이름도 같이 바뀝니다: `ch1` → `ch2`, `ch1_fader` → `ch2_fader`.
- 그룹 이름이 들어 있지 않은 안쪽 ID(`encoder3` 등)는 새 빈 이름을 받습니다. 그래서 Builder는 그룹 위에 놓은 위젯에 `ch1_encoder1`처럼 그룹 이름을 앞에 붙입니다.
- `params`의 숫자는 번호가 바뀐 만큼 커집니다: `ch: 1` → `ch: 2`. 스크립트는 그대로 복사됩니다. 그래서 `$ch`를 쓰는 스크립트는 고치지 않아도 다음 채널을 제어합니다.
- 복제본은 원본 바로 오른쪽(`x + w`)에 놓입니다.

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
| `$value` | 숫자 (label은 텍스트) | 값이 있는 모든 위젯 |
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
  "formatVersion": 1,
  "meta": { "name": "Studio A", "author": "Jimmy", "created": "2026-10-04T10:00:00Z" },
  "devices": {
    "mixer1": { "protocol": "tcp", "host": "192.168.0.10", "port": 5000 },
    "light1": { "protocol": "artnet", "host": "192.168.0.50", "universe": 0 }
  },
  "layouts": [
    {
      "id": "layout1", "name": "Tablet",
      "screen": { "width": 1280, "height": 800, "orientation": "landscape", "fit": "keep", "background": "#1E1E1E" },
      "pages": [
        {
          "id": "main",
          "name": "메인",
          "widgets": [
            {
              "id": "ch1_fader", "type": "fader", "orientation": "vertical",
              "x": 100, "y": 80, "w": 60, "h": 400,
              "value": { "min": 0, "max": 1, "step": 0, "default": 0.75 },
              "motion": { "touchMode": "relative", "sensitivity": 1.0, "resetOnDoubleTap": true, "sendInterval": 20 },
              "on": { "change": "set $level = round($value * 255)\nsend mixer1 \"SET CH1 VOL $level\\n\"" },
              "receive": [ { "device": "mixer1", "text": "CH1 VOL {n}", "value": "$n / 255" } ]
            },
            {
              "id": "ch1_mute", "type": "button", "mode": "toggle",
              "x": 100, "y": 500, "w": 60, "h": 40,
              "style": { "text": "MUTE", "color": "#D9534F" },
              "on": { "change": "if $value > 0\n    send mixer1 \"MUTE CH1 ON\\n\"\nelse\n    send mixer1 \"MUTE CH1 OFF\\n\"\nend" },
              "receive": [ { "device": "mixer1", "text": "CH1 MUTE {n}" } ]
            },
            {
              "id": "dimmer", "type": "encoder",
              "x": 300, "y": 80, "w": 120, "h": 120,
              "value": { "min": 0, "max": 255, "step": 1, "default": 0 },
              "motion": { "endless": false, "angleRange": 270, "drag": "vertical", "sensitivity": 1.0, "acceleration": true },
              "on": { "change": "dmx light1 1 ($value)" }
            },
            {
              "id": "go_scene2", "type": "button", "mode": "momentary",
              "x": 1100, "y": 700, "w": 140, "h": 60,
              "style": { "text": "Scene 2" },
              "on": { "press": "page \"scene2\"" }
            }
          ]
        },
        { "id": "scene2", "name": "장면 2", "widgets": [] }
      ]
    }
  ],
  "editor": { "grid": 10, "snap": true }
}
```

## 9. 정해지지 않은 것

- 패키지를 Player로 보내는 방법 (로컬 파일 / 서버 / 앱에 포함)
- 프로토콜별 장치 설정 키
- 현장에서 장치 주소를 바꾸는 Player 설정 화면
- 위젯 종류별 `style` 키 전체 목록과 테마
- 레이아웃 사이에서 구조 변경(복제, 그룹)을 맞춰 주는 도구
- 위젯 여러 개를 한 번에 바꾸는 스크립트 명령 (예: `set.widget ch1_fader 0.5`)이 필요한지
