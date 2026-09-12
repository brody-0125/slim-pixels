# slim_pixels

Dart에서 이미지의 크기와 형태를 변환하고 PNG, JPEG, WebP로 인코딩하는 라이브러리입니다. 바이트 배열을 입력받아 지정한 작업을 순서대로 수행하고, 인코딩된 바이트 배열을 반환합니다.

## 지원 범위

- Dart 3.10.0 이상, 4.0.0 미만
- Windows x64: 사전 빌드 DLL 및 소스 빌드
- Linux x64: 사전 빌드 공유 라이브러리 및 소스 빌드
- 입력: PNG/JPEG/WebP에서 디코딩한 RGB8 또는 RGBA8 이미지
- 작업: 크기 변경, 영역 자르기, 90도 단위 회전, 좌우·상하 반전
- 출력: PNG, JPEG, 무손실 WebP

호출은 동기식입니다. 파일 읽기·저장과 배치 작업의 동시성은 호출 측에서 관리합니다. Flutter에서는 큰 이미지를 처리할 때 worker isolate를 사용하세요. 모바일·macOS·ARM은 검증하지 않았습니다.

## 사용

현재는 로컬 경로 의존성으로 사용합니다. 포함된 네이티브 바이너리는 build hook이 해시를 확인하고 앱에 번들링합니다. pub.dev에는 아직 게시하지 않았습니다.

```yaml
dependencies:
  slim_pixels:
    path: ../slim-pixels
```

아래 예시는 가로·세로가 각각 512픽셀 이상인 이미지를 사용합니다.

```dart
import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';

final pixels = SlimPixels();
final output = pixels.transform(File('input.png').readAsBytesSync(), {
  'operations': [
    {'crop': {'x': 0, 'y': 0, 'width': 512, 'height': 512}},
    {'resize': {'width': 256, 'height': 256, 'filter': 'lanczos3'}},
  ],
  'format': 'jpeg',
  'quality': 90,
});
File('output.jpg').writeAsBytesSync(output);
```

`SlimPixels()`는 번들에 포함된 라이브러리를 로드합니다. 네이티브 바이너리의 ABI 버전을 확인한 뒤 처리 함수를 사용합니다. 직접 관리하는 바이너리는 기존 `SlimPixels(libraryPath)`로 열 수 있으며 ABI 1을 제공해야 합니다.

CLI 배포는 `dart build cli`를 사용하고 생성된 `bundle/` 전체를 옮기세요. build hook을 사용하는 패키지는 `dart compile exe`로 빌드할 수 없습니다. Dart 3.10의 `dart build cli`는 preview 명령입니다. Flutter 빌드·설치 결과물은 아직 검증하지 않았습니다.

바이너리를 자동 다운로드하지 않습니다. 포함된 바이너리가 없으면 먼저 소스 빌드를 수행하세요. 별도 로컬 번들은 소비자 앱의 `pubspec.yaml`에서 `hooks.user_defines.slim_pixels.native_directory`로 지정할 수 있습니다. 해당 디렉터리에는 대상 플랫폼의 두 라이브러리와 `SHA256SUMS.json`이 있어야 합니다. 사용자 지정 번들의 해시는 무결성 확인이며 배포자 인증은 아닙니다.

수동 로딩의 경우 Windows는 두 DLL을 같은 디렉터리에 두고 Linux는 코덱 검색 경로를 설정해야 합니다. 기본 번들 경로는 이러한 사용자 설정 없이 검증했습니다. 자세한 배포 조건과 남은 작업은 [배포 검증](docs/DISTRIBUTION.md)을 참고하세요.

## 요청 형식

`operations`, `format`, `quality`는 필수입니다. `scalar`는 선택이며 기본값은 `false`입니다. 알 수 없는 필드는 무시합니다.

| 항목 | 값과 동작 |
|---|---|
| 크기 변경 | `resize`: `width`, `height`, `filter`. 지정한 크기로 변환하며 종횡비는 자동 보존하지 않습니다. |
| 필터 | `lanczos3`: 주변 픽셀에 가중치를 적용하는 필터. `triangle`: 선형 가중치를 사용하는 필터. |
| 자르기 | `crop`: `x`, `y`, `width`, `height`. 현재 이미지 경계를 벗어나면 오류입니다. |
| 회전 | `rotate90`, `rotate180`, `rotate270`. 시계 방향입니다. |
| 반전 | `flip_horizontal`, `flip_vertical` |
| 출력 | `format`: `png`, `jpeg`, `webp` |
| 품질 | `quality`: 정수 0..255. JPEG에서는 1..100만 허용하며 PNG/WebP에서는 무시합니다. |
| 벡터 연산 | `scalar: true`이면 크기 변경의 SIMD 경로만 끕니다. JPEG 인코딩에는 적용하지 않습니다. |

## 처리 방식

이미지를 한 번 디코딩하고, 작업을 순서대로 적용한 뒤 인코딩합니다. 자르기 바로 다음에 크기 변경이 오는 경우 원본의 해당 영역을 빌려 읽어 중간 자르기 버퍼 복사를 생략합니다. 필터가 참조하는 경계는 자른 영역으로 유지합니다.

크기 변경은 주변 픽셀의 가중합으로 출력값을 계산하며, 지원되는 CPU에서는 여러 채널 값을 벡터 연산으로 처리합니다. 색상값과 알파 채널을 직접 계산하므로 선형 광량 변환이나 알파 사전 곱셈은 수행하지 않습니다.

Windows/Linux x64 기본 빌드의 RGB8 JPEG 품질 90 경로는 블록 단위 주파수 변환, 4:4:4 색상 샘플링, 이미지의 심벌 분포에 맞춘 부호표를 사용합니다. 다른 품질과 RGBA JPEG는 별도 인코딩 경로를 사용합니다. 결과 바이트가 다른 인코더와 같다는 보장은 없습니다.

입력과 결과는 Dart와 네이티브 코드 사이에서 복사됩니다. 반환 바이트는 Dart가 소유하며, 요청에 사용된 네이티브 결과·오류 버퍼와 인코더 자원은 요청 종료 시 해제합니다. 별도로 유지하는 이미지 핸들이 없어 `dispose` 호출은 필요하지 않습니다. 로드한 라이브러리 모듈은 유지됩니다.

## 제한과 오류

- 입력은 최대 256 MiB, 요청 JSON은 최대 64 KiB, 작업은 최대 64개입니다.
- 디코더의 가로·세로 제한은 각각 16,384픽셀, 할당 제한은 256 MiB입니다. 디코딩 후와 작업 출력에는 최대 3,200만 픽셀 제한을 검사합니다.
- 이 제한은 프로세스 전체 메모리 상한이 아닙니다. 복사본과 중간 버퍼가 함께 존재할 수 있습니다.
- grayscale/16-bit 자동 변환, 전체 애니메이션 프레임 처리, EXIF 방향 자동 적용, ICC 색상 관리, 메타데이터 보존은 지원하지 않습니다.
- JPEG의 투명도 배경 합성은 제공하지 않습니다. 필요하면 호출 측에서 처리해야 하며, 일부 입력은 코덱 오류로 반환될 수 있습니다.
- Dart 크기 검증은 `ArgumentError`, 네이티브 처리 오류는 `StateError`로 전달합니다. 로딩·직렬화 오류는 원래 예외로 전달합니다.
- OOM, Rust panic, 잘못된 C 포인터는 복구 가능한 API 오류로 보장하지 않습니다.

## 빌드와 검증

Windows 소스 빌드에는 MSVC 도구 체인과 Rust 1.97.1이 필요합니다.

```powershell
./tool/build.ps1
./tool/verify.ps1
```

Linux 빌드:

```sh
bash tool/build-linux.sh
```

[CI.md](CI.md)는 SDK·플랫폼별 실행 구성을, [GATES.md](GATES.md)는 출력·품질·메모리 게이트와 미검증 범위를 설명합니다. [로컬 검증 기록](docs/VALIDATION.md)은 원격 CI 실행 결과와 구분합니다. 실행 시간은 입력과 환경에 따라 달라지며, 측정된 커널 또는 인코딩 속도비를 앱 전체 성능으로 간주하지 않습니다.

## 문서와 라이선스

- [변경 기록](CHANGELOG.md)
- [기여 방법](CONTRIBUTING.md)
- [MIT 라이선스](LICENSE) — Copyright (c) 2026 Seokhyeon Kim
- [제3자 고지](THIRD_PARTY_NOTICES.md): 의존 코드의 라이선스와 출처를 별도로 보존합니다. 바이너리 배포 시 해당 고지와 `third_party/`를 함께 포함하세요.
