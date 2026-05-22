# 🎙️ 쉐도잉앱 (Shadowing App) — WIP

> 진행 중인 프로젝트입니다. 핵심 기능을 순차적으로 구현/문서화하고 있습니다. (마지막 업데이트: 2026-05-20)

## 📝 프로젝트 개요
영어/외국어 학습자를 위한 음성 쉐도잉 연습 애플리케이션으로 사용자가 스크립트를 보며 원문 오디오를 따라 말하고 발화 타이밍과 발음 정확도를 피드백 받는 경험을 제공함. SwiftUI와 iOS의 미디어 프레임워크를 활용해 간결한 UI와 자연스러운 녹음/재생 흐름을 목표.

## 📅 프로젝트 기간
* 2026.03.20 ~ (개발 진행 중)

## 💻 기술 스택
* **Platform:** iOS (최소 버전은 프로젝트 설정에 맞게 수정)
* **Language/Framework:** Swift, SwiftUI, Swift Concurrency(async/await)
* **Audio:** AVFoundation (AVAudioSession, AVAudioPlayer/Engine/Recorder 등)
* **Data:** (예정) 로컬 저장 SwiftData/CoreData 또는 파일 기반 저장
* **Others:** (선택) Speech, Combine, WidgetKit 등

## 🎯 주요 목표
- [ ] 스크립트/오디오 동기화 UI 구현 (문장/구간 단위 하이라이트)
- [ ] 원문 오디오 재생 및 사용자 음성 녹음 플로우 구축
- [ ] A-B 구간 반복, 재생 속도 조절(0.5x~1.5x)
- [ ] 기본 발화 피드백(타이밍, 길이) 제공
- [ ] 세션/진행 내역 저장 및 기록 화면
- [ ] (선택) 음성 인식/발음 평가 연동

## 🧱 시스템 설계 개요
1) 플레이어 & 레코더
- AVAudioSession 구성(카테고리/모드/옵션)
- 재생/일시정지/탐색, 구간 반복, 속도 조절
- 녹음 시작/중지, 파일 관리

2) 스크립트 동기화
- 문장별 타임스탬프 메타데이터 연동(예: JSON)
- 현재 재생 위치에 따른 하이라이트/자동 스크롤

3) 데이터 관리(초안)
- 세션 결과(날짜, 스크립트 ID, 구간별 점수/메모)
- 로컬 저장 우선, 추후 클라우드/동기화 검토

## 📁 디렉터리 구조(예시)
- /Sources/Audio — 오디오 세션/플레이어/레코더
- /Sources/Features/Shadowing — 쉐도잉 화면, 뷰모델, 동기화 로직
- /Sources/Models — 스크립트/타임스탬프/세션 모델
- /Resources/Scripts — 스크립트 및 타임스탬프(JSON)
- /Resources/Audio — 원문 오디오 파일
- /Docs/Screenshots — 스크린샷/프로토타입
## 🚀 실행 방법(개발용)
1. 저장소 클론 후 Xcode로 열기
2. 필요한 경우 SPM 의존성 Resolve
3. 시뮬레이터 또는 실제 기기에서 실행(마이크 권한 필요)
4. 오디오/스크립트 리소스가 없다면 샘플 데이터를 /Resources 폴더에 추가

권한 안내(Info.plist):
- NSMicrophoneUsageDescription: 마이크 사용 이유 명시
- (선택) NSSpeechRecognitionUsageDescription: 음성 인식 사용 시

## 🖥️ 스크린샷(예시)
이미지가 준비되면 아래 경로로 추가하고 링크를 업데이트하세요.

![메인 화면](Docs/Screenshots/main.png)
![쉐도잉 화면](Docs/Screenshots/shadowing.png)

## ⚠️ 현재 이슈/한계
1. 발음/정확도 평가는 기본 타이밍 기반으로 제공(정량 지표 고도화 예정)
2. 오디오/스크립트 메타데이터 제작 자동화 필요
3. 백그라운드 재생/인터럽션 처리 세부 정책 확정 전

## ✅ 로드맵
- UTF-8/지역화 대응(한/영 UI)
- 음성 인식(Speech) 또는 온디바이스 평가 연동 검토
- 학습 통계/히트맵, 위젯/라이브 액티비티(선택)
- 샘플 스크립트/오디오 번들링 및 문서화

## 🤝 기여
이슈/PR 환영합니다. 버그 리포트 시 재현 단계, 기대/실제 동작, 환경(iOS 버전/Xcode)을 포함해 주세요.

## 📄 라이선스
MIT (변경 가능)

## 📬 연락
- Maintainer: @hyeon-bs(수정)
- Issues: https://github.com/hyeon-bs/ShadowingApp/issues (수정)
