# 배포 검증

검토일: 2026-09-13. 기준: ABI 2 공개 API 작업 트리.

## 반영한 결정

- Dart 3.10을 유지하며 build hook과 Code Assets를 사용한다. link hook은 추가하지 않는다.
- Windows/Linux x64만 허용하고, 대상 OS/아키텍처로 번들을 선택한다.
- 패키지에 포함된 바이너리 또는 소비자가 지정한 로컬 번들을 사용한다. 다운로드·네트워크 재시도 로직은 없다.
- SHA256SUMS.json을 검사하고 코덱을 먼저 로드한다. 해시는 파일 변조·혼합을 검출하지만 함께 바뀐 매니페스트의 진위까지 보장하지 않는다.
- 기본 생성자는 번들링된 자산과 ABI 2를 요구한다. 런타임 경로 생성자는 제거했다. 사용자 지정 자산은 build hook의 native_directory로 제공한다.
- 패키지 버전과 ABI 버전은 별개다. ABI 또는 요청 계약의 호환성이 깨질 때 ABI 변경 여부를 검토한다.
- 코덱 정적 링크는 보류한다. 두 공유 라이브러리를 함께 번들링한 경로가 이미 동작하므로, 출력·크기·성능 비교 없이 링크 방식을 변경하지 않는다.

## 자동 게이트

`tool/distribution_check.py [dart executable]`는 별도 임시 소비자에 런타임 패키지를 복사하고 다음을 검사한다.

1. 경로 없는 생성자로 JIT에서 JPEG 기준 바이트 일치.
2. 매니페스트 변경에 따른 hook 캐시 무효화와 잘못된 해시 거부.
3. `dart build cli`로 코드 자산 두 개를 번들링.
4. 소스·소비자 캐시를 삭제하고 번들을 다른 디렉터리로 이동.
5. 라이브러리 환경 변수와 개발 도구 PATH 없이 결과물에서 JPEG 기준 바이트 일치.

호스트 자체를 새 VM으로 만드는 검사는 아니므로 이미 설치된 OS 런타임의 존재까지 배제하지 않는다. Flutter release 앱, 모바일, macOS, ARM은 범위 밖이다.

기존 AOT 검사는 `tool/aot_check.py`가 임시 bin 진입점을 만든 뒤 `dart build cli`로 수행한다. `dart compile exe`는 build hook을 지원하지 않는다. SDK CI의 모든 버전/OS 조합에서 소비자 게이트를 실행한다. main의 b01b24f는 [원격 CI](https://github.com/brody-0125/slim-pixels/actions/runs/34758504730)를 통과했다. 릴리스 브랜치 최종 커밋은 별도로 검증해야 한다.

## 릴리스

버전과 일치하는 v 태그를 push하면 전체 required 게이트 성공 후 동일한 native artifact를 받아 `tool/release_bundle.py`로 플랫폼별 zip을 만든다. SHA256SUMS, ABI/소스 커밋 메타데이터, 라이선스·제3자 고지가 포함된다. GitHub에는 draft release로 올리며 pub.dev 게시와 공개 전환은 하지 않는다. 기존 draft가 같은 태그로 있으면 생성이 실패하므로 재실행 전에 기존 draft 상태를 확인해야 한다.

0.1.2는 v0.1.2 태그와 GitHub draft release, pub.dev 게시를 마쳤다. 0.1.3은 같은 태그·draft release 절차를 따른다. 게시 전 최종 패키지 구성에서 dry-run을 완료해야 한다.

## 아직 남은 배포 조건

- Windows 코덱은 기존 바이너리이며 원래 컴파일 옵션이 없다. 소스 재현 빌드라고 주장하지 않는다. 향후 고정 소스/도구 체인으로 대체하려면 기존 인코딩·품질 게이트를 통과해야 한다. 이번 번들은 기존 DLL과 그 출처 고지를 유지한다.
- Linux x64는 glibc 환경에서 검증했다. glibc 최소 버전, Alpine/musl 지원은 확정하지 않았다. Ubuntu 24.04 CI 결과만으로 다른 배포판 지원을 추정하지 않는다.
- Windows 최소 OS/런타임 요구와 SIMD 미지원 CPU에서의 바이너리 실행 검증이 남아 있다.
- 다운로드 기본값은 안정적인 공개 릴리스 URL과 패키지 내 고정 해시를 확보한 뒤 추가한다.
- Linux의 조작한 바이너리 6종으로 ABI 불일치·로딩·심볼·메타데이터·오류 위치·인코딩 실패를 검사한다. Windows에서 같은 실패 주입의 실행 검증은 남아 있다.

## 참고

- https://dart.dev/tools/hooks — build hooks 3.10, link hooks 3.13.
- https://docs.flutter.dev/platform-integration/bind-native-code — code asset 번들링.
- https://pub.dev/documentation/sqlite3/latest/topics/hook-topic.html — 버전별 바이너리와 고정 해시 배포.

## ABI 1 시점의 과거 로컬 실행 결과

아래는 30229b5까지의 기록이다. ABI 2 검증 결과는 [VALIDATION.md](VALIDATION.md)의 현재 기록을 따른다.

- Windows/Linux x64 × Dart 3.10.0/3.13.3: 소비자 JIT, 해시 불일치 거부, 이동한 AOT 번들 통과.
- Windows JIT(3.13.2)/AOT(3.13.3), Linux JIT/AOT(3.13.3): 각각 334개 골든 및 JPEG 1,000회 반복 통과.
- Dart 3.10 및 3.13 분석, Rust 포맷 검사, actionlint 통과. Windows Rust 단위 테스트 4개 통과.
- 릴리스 zip 두 개 생성·번들 해시 확인 통과. 기존 코덱의 출력 골든을 변경하지 않음.
- pub dry-run은 오류 없이 완료되지만 repository URL, 변경 파일, docs 디렉터리 이름 경고가 남음. pub.dev 게시 준비 완료를 의미하지 않음.

## 0.1.3 게시 후보

native/bin은 cad4070의 성공한 CI 실행 [35445782352](https://github.com/brody-0125/slim-pixels/actions/runs/35445782352)에서 내려받은 Windows/Linux artifact와 SHA256SUMS.json을 사용합니다. 커밋된 0.1.2 번들과 바이트가 달라 동일 산출물로 교체했습니다. Windows `turbojpeg.dll` 해시는 기존 코덱과 같습니다. 코덱 출처와 지원 플랫폼 제한은 THIRD_PARTY_NOTICES.md 및 위 배포 조건을 따릅니다. 버전은 0.1.3, ABI는 2입니다. 태그 생성과 pub.dev 게시는 별도 단계입니다.
