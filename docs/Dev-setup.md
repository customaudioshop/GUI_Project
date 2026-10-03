# 개발 환경 설정 (Mac / Windows)

이 저장소는 집 Mac, 사무실 Mac, 사무실 Windows PC에서 같이 씁니다.

## 왜 설정이 필요한가

Builder와 Player가 공용 코드 `shared/gui_core/`를 함께 씁니다. Godot 프로젝트는 자기 폴더 밖의 파일을 읽지 못하므로, 각 프로젝트 안에 이 폴더를 가리키는 **심볼릭 링크**를 두었습니다.

```
gui-builder/gui_core  ->  ../shared/gui_core
gui-player/gui_core   ->  ../shared/gui_core
```

Mac은 설정 없이 그대로 동작합니다. **Windows는 처음 한 번 아래 설정이 필요합니다.** 설정하지 않으면 `gui_core`가 링크가 아니라 경로 한 줄이 적힌 작은 텍스트 파일로 받아져서, Godot에서 `GuiPackage`를 찾을 수 없다는 오류가 납니다.

## Windows: 처음 한 번

1. **개발자 모드 켜기**: 설정 → 시스템(또는 개인 정보 및 보안) → 개발자용 → **개발자 모드** 켬.
   관리자 권한 없이 심볼릭 링크를 만들 수 있게 됩니다.
2. **git에서 심볼릭 링크 켜기** (PowerShell 또는 명령 프롬프트):
   ```
   git config --global core.symlinks true
   ```
   Git for Windows 설치 화면의 "Enable symbolic links"에 체크한 것과 같습니다.
3. **저장소 받기**
   - 처음 받는 경우: `git clone https://github.com/customaudioshop/GUI_Project.git`
   - 이미 받아 둔 경우: 잘못 받아진 두 파일을 지우고 다시 꺼냅니다.
     ```
     cd GUI_Project
     del gui-builder\gui_core gui-player\gui_core
     git checkout -- gui-builder/gui_core gui-player/gui_core
     ```
4. **확인**: `dir gui-builder`에서 `gui_core`가 `<SYMLINKD>`로 보이면 성공입니다.

## Claude 메모리 공유 (선택)

Claude Code 메모리는 저장소의 `.claude/memory/`에 있습니다. 각 컴퓨터의 Claude Code가 이 폴더를 읽도록 링크를 겁니다. 폴더 이름은 프로젝트 경로에서 만들어지므로, 그 컴퓨터에서 Claude Code를 이 프로젝트로 한 번 연 뒤 `~/.claude/projects/`(Windows는 `%USERPROFILE%\.claude\projects\`)에서 확인합니다.

- Mac:
  ```
  ln -s "$PWD/.claude/memory" ~/.claude/projects/<폴더 이름>/memory
  ```
- Windows (개발자 모드에서, 명령 프롬프트):
  ```
  mklink /D "%USERPROFILE%\.claude\projects\<폴더 이름>\memory" "%CD%\.claude\memory"
  ```

링크를 걸기 전에 원래 `memory` 폴더가 있으면 그 내용을 `.claude/memory/`로 옮긴 다음 지웁니다.

## 매일

- 시작할 때: `git pull`
- 끝낼 때: 커밋 후 `git push`
