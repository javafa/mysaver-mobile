# 모바일 공통 상수

iOS / Android 양쪽에서 일치시켜야 하는 값들. 코드를 직접 공유하지 않으므로, 한 곳을 바꾸면 양쪽 모두 업데이트할 것.

| 키 | 값 | 위치 |
|---|---|---|
| 사이트 URL (prod) | `https://mysaver.kr` | iOS `AppConfig.swift`, Android `AppConfig.kt` |
| 허용 호스트 (prod) | `mysaver.kr` | iOS `AppConfig.swift`, Android `AppConfig.kt` |
| API base URL (prod) | `https://api.mysaver.kr` | iOS `ShareConfig.apiBase`, Android `AppConfig.API_BASE`. 사이트와 다른 서브도메인 — 혼동 주의 |
| iOS App Group ID | `group.kr.mysaver.shared` | iOS `AppConfig.swift`, `*.entitlements` |
| iOS URL scheme | `mysaver://` | iOS `AppConfig.swift` |
| 공유 URL 키 | `pending_share_url` | iOS App Group UserDefaults, Android SharedPreferences |
| 토큰 키 | `auth_token` | iOS App Group UserDefaults, Android SharedPreferences |
| Android SharedPreferences 이름 | `mysaver_prefs` | Android `AppConfig.kt` |
| Android package | `kr.mysaver.android` | Android `build.gradle.kts` `applicationId` |

## Share Sheet (iOS Share Extension / Android ShareActivity)

iOS `mobile/ios/MySaverShare/` 와 Android `mobile/android/app/.../Share*` 는 동일한 와이어프레임("share-sheet-redesign")을 구현. 호출 API 동일.

### 호출 백엔드 API

| 메서드 | 경로 | 용도 |
|---|---|---|
| `GET` | `/api/items/preview?url=<url>` | URL → og:image / 제목 / 도메인 / 플랫폼 미리보기. 200 항상 반환(필드만 null). |
| `GET` | `/api/folders/` | 폴더 목록 |
| `POST` | `/api/items/sync` | 아이템 저장 (note/tags/thumbnailUrl 포함) |
| `POST` | `/api/folders/{id}/items` | 폴더 연결 (선택 시) |

### UI 컴포넌트 매핑

| 와이어프레임 영역 | iOS (SwiftUI) | Android (View) |
|---|---|---|
| 시트 컨테이너 | 시스템이 Share Extension 모달로 표시 | `BottomSheetDialogFragment` |
| 메인 뷰 | `ShareSheetView.swift` | `fragment_share_sheet.xml` + `ShareSheetFragment.kt` |
| 상태 홀더 | `SharePreviewModel.swift` (`ObservableObject`) | `SharePreviewViewModel.kt` (`ViewModel` + `StateFlow`) |
| API 클라이언트 | `ShareAPI.swift` | `ShareApi.kt` |
| 폴더 피커 | `FolderPickerSheet.swift` (`.sheet`) | `FolderPickerBottomSheet.kt` |
| 썸네일 로딩 | `AsyncImage` | Coil (`io.coil-kt:coil`) |

### 의도적 미구현

- **리마인드** — 와이어프레임에 UI 만 존재. 백엔드 컬럼/스케줄러 미준비 (`backend/CLAUDE.md` "미구현" 표 참조).
- **태그 자동 분류** — Phase 1 은 `uncategorized` 만. 분류 OpenAI 호출은 별 도 작업.

## Web → Native 브릿지 계약

웹 프론트엔드(`frontend/`)에서 다음 함수를 호출해 네이티브 쉘과 통신.

### 로그인 후 토큰 저장

```javascript
// iOS
if (window.webkit?.messageHandlers?.mysaver) {
  window.webkit.messageHandlers.mysaver.postMessage({ type: 'setToken', token: jwt });
}

// Android
if (window.MySaverNative?.setToken) {
  window.MySaverNative.setToken(jwt);
}
```

### 로그아웃 시 토큰 제거

```javascript
// iOS
window.webkit?.messageHandlers?.mysaver?.postMessage({ type: 'clearToken' });
// Android
window.MySaverNative?.clearToken?.();
```

### Share Extension 으로부터 공유된 URL 수신

```javascript
window.addEventListener('mysaver:shared', (event) => {
  const sharedUrl = event.detail.url;
  // 백엔드 sync API 호출 등으로 저장 처리.
});
```

### 소셜 로그인 (모바일 쉘 안)

WebView 안에서 Google OAuth 를 띄울 수 없으므로(disallowed_useragent), 네이티브에 위임:

```javascript
// 모바일 쉘 안에서 소셜 버튼 클릭 시:
//   iOS: window.webkit.messageHandlers.mysaver.postMessage({ type: 'openOAuth', provider })
//   Android: window.MySaverNative.openOAuth(provider)
// → 네이티브가 ASWebAuthenticationSession / Chrome Custom Tabs 로
//   https://mysaver.kr/login?platform=<ios|android>&autoOauth=<provider> 를 열어줌
// → OAuth 완료 후 프론트의 /auth/<provider>/callback 페이지가
//   mysaver://oauth?token=&user=&isNewUser=&hasHandle= 로 redirect
// → 네이티브가 토큰/유저를 메인 WebView 의 localStorage 에 주입하고 라우팅
```

전체 흐름은 `frontend/src/lib/mobileShell.ts` + `mobile/ios/ios/OAuthCoordinator.swift` + `mobile/android/app/src/main/java/kr/mysaver/android/MainActivity.kt` 참고.

## 모바일 환경 감지

웹 프론트엔드가 네이티브 쉘 안에서 도는지 알고 싶을 때:

```javascript
const isIOSShell = !!window.webkit?.messageHandlers?.mysaver;
const isAndroidShell = !!window.MySaverNative;
const isInMobileShell = isIOSShell || isAndroidShell;
```

또는 User-Agent 로 (Android 는 UA 에 `MySaverApp/1.0` 을 붙임).
