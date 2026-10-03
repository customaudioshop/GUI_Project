# GuiScript 명세 (v0.1)

GuiScript는 GUI Builder 사용자가 위젯 이벤트(버튼 클릭, 페이더 이동 등)에 연결하는 간단한 명령 언어입니다.

- 사용자는 C#/GDScript를 쓰지 않고 GuiScript만 씁니다.
- 명령의 실제 동작은 개발자가 C#으로 구현하고 `CommandRegistry`에 등록합니다.
- 패키지에는 실행 코드가 아닌 텍스트 스크립트만 들어가므로 iOS/앱스토어 제약이 없습니다.
- 반복 횟수가 고정이고 `while`이 없으므로 **모든 스크립트는 반드시 끝납니다.**

구현: `shared/GuiScript/` (Godot 비의존 C# 라이브러리), 테스트: `shared/GuiScript.Tests/`

## 1. 예시

```
# 페이더 이동: 믹서 볼륨과 조명 밝기 조절
set $level = round(scale($value, 0, 1, 0, 255))
send mixer1 "SET CH1 VOL $level\n"
dmx light1 1 ($level)

if $value > 0.5
    gpio relay 3 on
elif $value > 0.2
    midi.cc synth 1 7 (round($value * 127))
else
    gpio relay 3 off
end

repeat 3
    ir tv "power"
    wait 200
end
page "scene2"
```

## 2. 기본 규칙

| 항목 | 규칙 |
|---|---|
| 문장 | 한 줄에 한 문장 |
| 주석 | `#`부터 줄 끝까지 |
| 들여쓰기 | 자유 (의미 없음, 가독성용) |
| 대소문자 | 구분함 (`Send` ≠ `send`) |

## 3. 값과 타입

| 타입 | 예 |
|---|---|
| 숫자 | `10`, `0.5`, `-3`, `0xFF` |
| 텍스트 | `"SET CH1"`, 안에 `$변수` 사용 가능, 이스케이프 `\n \t \" \\ \$` |
| 참/거짓 | `true`, `false` |
| 변수 | `$level` (`$` + 영문/숫자/`_`) |
| 이름 | `mixer1`, `on` — 따옴표 없는 이름은 장치 이름이나 선택값에만 사용 |

## 4. 문장

```
명령 인자1 인자2 ...          # 예: dmx light1 1 255
set $변수 = 식
if 조건 / elif 조건 / else / end
repeat 횟수 / end            # 횟수는 1~1000의 고정 숫자
```

**인자는 공백으로 구분되므로, 계산식은 괄호로 감싸야 합니다.**

```
dmx light1 1 ($value * 2)    # ✅
dmx light1 1 $value * 2      # ❌ GS201: 괄호 필요
```

## 5. 연산자 (우선순위 낮은 순)

`or` → `and` → `not` → `== != < <= > >=` → `+ -` → `* / %` → 단항 `-`

- `+`는 한쪽이 텍스트면 이어 붙이기: `"CH" + 1` → `"CH1"`
- 조건(`if`)은 반드시 참/거짓이어야 합니다. `if $value` ❌ → `if $value > 0` ✅

## 6. 기본 명령

| 명령 | 사용법 | 장치 프로토콜 |
|---|---|---|
| `send` | `send <device> <data>` | tcp, udp, serial |
| `sendhex` | `sendhex <device> "01 A0 FF"` | tcp, udp, serial |
| `dmx` | `dmx <device> <channel 1-512> <value 0-255>` | artnet, sacn, dmx-usb |
| `dmx.fade` | `dmx.fade <device> <channel> <value> <ms 0-60000>` | artnet, sacn, dmx-usb |
| `midi.note` | `midi.note <device> <channel 1-16> <note 0-127> <velocity 0-127>` | midi |
| `midi.cc` | `midi.cc <device> <channel> <controller 0-127> <value 0-127>` | midi |
| `midi.pc` | `midi.pc <device> <channel> <program 0-127>` | midi |
| `gpio` | `gpio <device> <pin 0-63> on\|off` | gpio |
| `ir` | `ir <device> "<코드 이름>"` | ir |
| `wait` | `wait <ms 0-60000>` | — |
| `page` | `page "<페이지 이름>"` | — |
| `log` | `log <message>` | — |

## 7. 기본 함수

`clamp(v, min, max)`, `min(a, b)`, `max(a, b)`, `round(v)`, `floor(v)`, `ceil(v)`, `abs(v)`,
`scale(v, inMin, inMax, outMin, outMax)`, `str(v)`, `num(text)`

## 8. 검증 단계

`ScriptChecker.Check(source, context)` 한 번 호출로 4단계를 모두 수행합니다. 오류가 있어도 멈추지 않고 가능한 한 모든 오류를 줄/칸 위치와 함께 보고합니다.

| 단계 | 검사 내용 |
|---|---|
| 1. 어휘 (GS1xx) | 잘못된 문자, 닫히지 않은 텍스트, 잘못된 숫자/이스케이프 |
| 2. 구문 (GS2xx) | 문장 구조, `if`/`repeat`의 `end` 짝 |
| 3. 의미 (GS3xx) | 명령 존재 여부, 인자 개수/타입/범위, 장치 존재 및 프로토콜 일치, 변수 정의 여부, 페이지 존재 |
| 4. 안전 제한 (GS4xx) | 최대 줄 수(500), 중첩 깊이(8), 반복 횟수(1~1000, 고정값만) |

오타에는 가장 가까운 이름을 제안합니다. 예: `sned` → "Did you mean 'send'?"

### 검증 컨텍스트

스크립트는 패키지 정보와 함께 검증됩니다.

```csharp
var context = new ValidationContext
{
    Devices = { ["mixer1"] = Protocols.Tcp, ["light1"] = Protocols.ArtNet },
    Pages = { "main", "scene2" },
    ContextVariables = { ["value"] = ScriptType.Number },  // 위젯이 제공하는 읽기 전용 변수
};
var result = ScriptChecker.Check(scriptText, context);
if (!result.IsValid)
    foreach (var d in result.Diagnostics)
        Console.WriteLine(d);   // 2:14 error GS304: <channel> must be from 1 to 512, got 600
```

### 정적 검증의 한계 → 실행 시 검사 필요

`$value`처럼 실행 중에만 알 수 있는 값은 범위를 미리 검사할 수 없습니다. 예를 들어 `dmx light1 1 ($value * 300)`은 검증을 통과합니다. 그래서 **인터프리터(다음 단계)가 실행 시에도 같은 `ParamSpec` 범위를 다시 검사**해야 합니다.

### Player의 재검증 원칙

Player는 Builder의 검증 결과를 믿지 않고 **패키지를 불러올 때 모든 스크립트를 다시 검증**합니다. 오류가 있는 스크립트는 실행하지 않습니다. 패키지 파일은 손으로 수정되거나 다른 버전의 Builder에서 만들어졌을 수 있기 때문입니다.

## 9. 개발자: 명령 추가하기

파서를 고칠 필요 없이 등록만 하면 검증기가 자동으로 검사합니다.

```csharp
context.Commands.Register("mixer.mute", "Mute a mixer channel",
    ParamSpec.Device("device", Protocols.Tcp),
    ParamSpec.Int("channel", 1, 32),
    ParamSpec.Bool("muted"));
// 사용자: mixer.mute mixer1 4 true
```

인자 종류: `Int`, `Number`, `Text`, `Bool`, `AnyValue`, `Device(프로토콜...)`, `Choice(값...)`, `Page`, `Hex`

## 10. 오류 코드

| 코드 | 의미 | 코드 | 의미 |
|---|---|---|---|
| GS101 | 잘못된 문자 | GS304 | 범위 초과 |
| GS102 | 텍스트 닫는 `"` 없음 | GS305 | 없는 장치 |
| GS103 | 잘못된 이스케이프 | GS306 | 장치 프로토콜 불일치 |
| GS104 | 잘못된 숫자 | GS307 | 정의되지 않은 변수 |
| GS105 | `$` 뒤 변수 이름 없음 | GS308 | 없는 함수 |
| GS201 | 예상치 못한 토큰 | GS309 | 읽기 전용 변수 변경 |
| GS202 | `end` 누락 | GS310 | 없는 페이지 |
| GS203 | 짝 없는 `elif/else/end` | GS311 | 잘못된 hex |
| GS204 | 값이 와야 함 | GS312 | 잘못된 선택값 |
| GS205 | 줄 끝이 와야 함 | GS313 | 0으로 나누기 |
| GS206 | `set` 뒤 변수 없음 | GS314 | 정수가 아님 |
| GS207 | `=` 없음 | GS315 | 변수 타입 변경 |
| GS208 | `)` 없음 | GS316 | 값 자리에 이름 사용 |
| GS301 | 없는 명령 | GS401 | 줄 수 초과 |
| GS302 | 인자 개수 오류 | GS402 | 중첩 깊이 초과 |
| GS303 | 타입 불일치 | GS403 | 반복 횟수가 고정값 아님 |
| | | GS404 | 반복 횟수 범위 초과 |
| | | GS501 | (경고) 항상 같은 조건 |

오류 메시지는 현재 영어입니다. 코드가 고정되어 있으므로 Builder에서 코드별로 한국어 등 다른 언어 메시지로 바꿔 보여줄 수 있습니다.
