# MySaver Mobile

iOS / Android 네이티브 쉘 + WebView 기반 모바일 앱.

```
mobile/
├── ios/
│   ├── ios/                    # 메인 앱 (WKWebView)
│   │   ├── iosApp.swift
│   │   ├── ContentView.swift
│   │   ├── WebViewContainer.swift
│   │   ├── AppConfig.swift
│   │   ├── SharedStore.swift
│   │   └── ios.entitlements    # App Group
│   ├── MySaverShare/           # Share Extension (Xcode target 별도 추가 필요)
│   │   ├── ShareViewController.swift
│   │   ├── Info.plist
│   │   └── MySaverShare.entitlements
│   └── ios.xcodeproj/
├── android/
│   └── app/src/main/
│       ├── java/kr/mysaver/android/
│       │   ├── MainActivity.kt       # WebView 컨테이너
│       │   ├── ShareActivity.kt      # SEND intent 처리
│       │   ├── AppConfig.kt
│       │   └── SharedStore.kt
│       └── AndroidManifest.xml
├── shared/
│   └── constants.md            # 양쪽 공통 상수 + 브릿지 계약
└── README.md
```

## 아키텍처 개요

- **메인 화면**: 웹 프론트엔드(`https://mysaver.kr`)를 그대로 WebView 에 렌더링.
- **공유 기능**: iOS Share Extension / Android Share Activity 가 다른 앱에서 공유된 URL 을 받아 백엔드 `/api/items/sync` 에 POST. 토큰이 없으면 메인 앱을 열어서 동기화 위임.
- **인증**: 웹에서 로그인 → JS 브릿지로 JWT 를 네이티브 저장소에 전달 → Share Extension 이 같은 저장소에서 토큰 읽어서 API 호출.
- **OAuth (Google/Kakao/Naver)**: Google 이 WebView 안 `accounts.google.com` 접속을 차단 (`disallowed_useragent`) 하므로, 시스템 브라우저에서 OAuth 를 돌리고 custom URL scheme 으로 복귀:
  - iOS: `ASWebAuthenticationSession` (callbackURLScheme=`mysaver`)
  - Android: `Chrome Custom Tabs` + `mysaver://oauth` intent-filter
  - 흐름: WebView 소셜버튼 → `openOAuth` 브릿지 → 시스템 브라우저로 `/login?platform=<ios|android>&autoOauth=<provider>` 열기 → OAuth 완료 → 프론트가 `mysaver://oauth?token=&user=&isNewUser=&hasHandle=` 로 redirect → 네이티브가 토큰/유저를 메인 WebView 의 localStorage 에 주입하고 라우팅

자세한 브릿지 계약은 [shared/constants.md](shared/constants.md) 참고.

---

## iOS

### 빌드 / 실행

```bash
cd mobile/ios
open ios.xcodeproj
```

Xcode 에서 빌드 ▶ — 메인 앱은 그대로 실행됨.

### Share Extension target 추가 (1회)

Share Extension 코드는 `mobile/ios/MySaverShare/` 에 있지만, Xcode 의 target 구성은 별도로 해줘야 함.

1. Xcode 에서 `ios.xcodeproj` 열기
2. `File → New → Target…` → **Share Extension** 선택 → Next
3. Product Name: `MySaverShare`, Language: Swift, Project: `ios` → Finish
4. Activate scheme 묻는 다이얼로그는 **Cancel** (메인 앱 scheme 유지)
5. 새로 생긴 `MySaverShare/` 그룹에서 Xcode 가 자동 생성한 파일 삭제 (`Move to Trash`):
   - `ShareViewController.swift`
   - `MainInterface.storyboard`
   - `Info.plist`
6. Finder 에서 `mobile/ios/MySaverShare/` 의 파일들(`ShareViewController.swift`, `Info.plist`, `MySaverShare.entitlements`)을 Xcode 의 `MySaverShare` 그룹으로 드래그 → "Copy items if needed" **체크 해제**, "Add to targets: MySaverShare" 체크 → Finish
7. `MySaverShare` target 선택 → **Build Settings** → `Info.plist File` 을 `MySaverShare/Info.plist` 로, `Code Signing Entitlements` 를 `MySaverShare/MySaverShare.entitlements` 로 설정
8. **Build Settings** → `Skip Install` 을 `Yes` 확인 (Share Extension 기본값)

### App Group 설정 (메인 앱 + Share Extension 양쪽)

App Group 으로 메인앱 ↔ Share Extension 간 JWT/URL 을 공유.

1. Xcode 에서 `ios` target → **Signing & Capabilities** → `+ Capability` → **App Groups**
2. `+` 버튼 → `group.kr.mysaver.shared` 추가
3. `MySaverShare` target 에서도 동일하게 추가
4. (이미 작성된 `*.entitlements` 파일이 자동 인식되어 체크박스가 켜져 있어야 함)

> **주의**: 개인 Apple 계정으로는 App Group 등록 불가. 유료 Apple Developer Program 가입 후 Bundle ID 별로 등록해야 함.

### URL Scheme 등록 (Share Extension → 메인 앱 호출용)

1. Xcode 에서 `ios` target → **Info** 탭 → `URL Types` → `+`
2. URL Schemes: `mysaver`, Identifier: `kr.mysaver.urlscheme` 등록

### 개발 모드 (localhost)

기본은 prod (`https://mysaver.kr`) 로 로드. 로컬 dev 서버를 쓰려면:

1. `mobile/ios/ios/AppConfig.swift` 의 `#if DEBUG` 블록 주석 해제
2. Xcode `ios` target → **Info** → `App Transport Security Settings` → `Allow Local Networking` 추가 (BOOL = YES)

---

## Android

### 빌드 / 실행

```bash
cd mobile/android
./gradlew assembleDebug
# 또는 Android Studio 에서 Run ▶
```

`./gradlew installDebug` 로 연결된 디바이스/에뮬레이터에 설치.

### Share 동작 확인

1. 앱 한 번 실행해서 웹 로그인 (토큰이 SharedPreferences 에 저장됨)
2. 다른 앱(Chrome 등)에서 URL 공유 → **MySaver** 선택
3. Toast 로 결과 표시 후 자동 종료

### 개발 모드 (localhost)

Android 에뮬레이터에서 호스트 머신의 localhost 접근은 `10.0.2.2`:

1. `mobile/android/app/src/main/java/kr/mysaver/android/AppConfig.kt` 의 `SITE_URL` 을 `"http://10.0.2.2:3000"` 으로 변경
2. `AndroidManifest.xml` 의 `<application>` 태그에 `android:usesCleartextTraffic="true"` 추가

---

## 프론트엔드 통합 작업 (`frontend/`)

웹 프론트엔드 쪽에서 네이티브 쉘과 연동하려면 다음을 해야 함:

1. **로그인 후 JWT 를 네이티브로 전달**
   ```typescript
   // login 성공 직후
   const w = window as any;
   if (w.webkit?.messageHandlers?.mysaver) {
     w.webkit.messageHandlers.mysaver.postMessage({ type: 'setToken', token });
   } else if (w.MySaverNative?.setToken) {
     w.MySaverNative.setToken(token);
   }
   ```

2. **공유 이벤트 수신**
   ```typescript
   useEffect(() => {
     const handler = (e: CustomEvent<{ url: string }>) => {
       syncSharedUrl(e.detail.url); // 백엔드 /api/items/sync 호출
     };
     window.addEventListener('mysaver:shared', handler as EventListener);
     return () => window.removeEventListener('mysaver:shared', handler as EventListener);
   }, []);
   ```

3. **모바일 쉘 감지** (앱 다운로드 배너 숨기기 등)
   ```typescript
   const isInMobileShell =
     !!(window as any).webkit?.messageHandlers?.mysaver ||
     !!(window as any).MySaverNative;
   ```

자세한 계약은 [shared/constants.md](shared/constants.md).

---

## 알려진 한계 / TODO

- [ ] iOS Share Extension target 을 Xcode 에서 1회 수동 설정 필요 (위 절차 참고)
- [ ] App Store 4.2 Minimum Functionality 통과를 위한 네이티브 가치 추가 (푸시 알림, 오프라인 캐시 등) — 추후 작업
- [ ] iOS/Android 푸시 알림 미구현
- [ ] 딥링크 (`mysaver://item/<id>` 등) 미구현 — `/setup-handle`, `/welcome` 같은 라우트 직접 진입용
- [ ] iOS WebView 의 cookie/localStorage 가 Share Extension 의 `URLSession` 과 분리되어 있음 — JWT 는 명시적으로 App Group 에 동기화해야 함 (위 브릿지로 해결)
