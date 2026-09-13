# slim_pixels

Dart에서 이미지의 크기와 형태를 변환하고 PNG, JPEG, 무손실 WebP로 인코딩합니다. 인코딩된 바이트와 타입이 있는 작업 목록을 받아, 읽기 전용 바이트와 출력 메타데이터를 반환합니다.

## 지원 범위

- Dart 3.10.0 이상, 4.0.0 미만. Windows/Linux x64 네이티브 자산을 포함합니다.
- 입력: 정적 PNG/JPEG/WebP에서 디코딩한 RGB8/RGBA8.
- 작업: exact/inside/cover resize, crop, 90도 단위 회전, 좌우·상하 반전.
- 출력: JPEG, PNG, 무손실 WebP.

동기 호출은 `SlimPixels.transformSync`, 재사용하는 비동기 호출은 `SlimPixelsWorker.transform`으로 제공합니다. 파일 I/O와 배치 동시성은 호출자가 관리합니다. Flutter 설치 결과물·모바일·macOS·ARM은 검증하지 않았습니다.

## 사용

아직 pub.dev에 게시하지 않았습니다. 로컬 경로 의존성으로 사용할 수 있습니다.

```yaml
dependencies:
  slim_pixels:
    path: ../slim-pixels
```

```dart
import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';

void main() {
  final pixels = SlimPixels();
  final result = pixels.transformSync(
    File('input.png').readAsBytesSync(),
    operations: [Resize.inside(maxWidth: 512, maxHeight: 512)],
    encoding: const WebpLosslessEncoding(),
  );
  File('output.webp').writeAsBytesSync(result.bytes);
  print('${result.width}x${result.height}, ${result.mimeType}');
}
```

`encoding`은 필수입니다. 작업 목록을 생략해도 이미지를 다시 디코딩하고 인코딩합니다. 원본 바이트나 메타데이터를 보존하는 기능이 아닙니다. 결과 바이트를 수정하려면 `Uint8List.fromList(result.bytes)`로 복사하세요. `SlimPixels`에는 `dispose`가 필요하지 않습니다. worker는 사용 후 `close()`를 호출하세요.

## 재사용하는 비동기 worker

```dart
import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';

Future<void> main() async {
  final worker = await SlimPixelsWorker.start();
  try {
    final result = await worker.transform(
      await File('input.png').readAsBytes(),
      operations: [Resize.inside(maxWidth: 512)],
      encoding: JpegEncoding(quality: 90),
    );
    await File('output.jpg').writeAsBytes(result.bytes);
  } finally {
    await worker.close();
  }
}
```

worker 하나는 isolate 하나에서 순서대로 처리합니다. 기본 한도는 실행 중인 요청을 포함해 4개, 입력 합계 256 MiB이며 `start(maxPendingRequests:, maxPendingInputBytes:)`로 조정합니다. 초과 요청은 복사·대기열 등록 전에 `workerCapacityExceeded`로 실패합니다. 큰 배치는 각 결과를 await하거나 호출자가 제한된 수만 제출하세요.

`transform`이 반환되기 전에 입력과 작업 목록을 스냅샷하므로 이후 원본을 수정할 수 있습니다. 복사 비용이 있어 호출 자체가 무비용인 것은 아닙니다. 결과는 읽기 전용이며 zero-copy를 보장하지 않습니다. 한도는 전체 RSS나 호출자가 보관하는 결과의 합계를 제한하지 않습니다.

`close()`는 신규 요청을 차단하고 수락한 요청을 모두 처리한 뒤 종료합니다. 반복 호출할 수 있습니다. 이후 `transform`은 Future의 `StateError`로 실패합니다. 일반 이미지 오류 후에는 재사용할 수 있지만 예기치 않은 worker 종료는 대기 작업을 `workerTerminated`로 실패시키며 자동 재시도하지 않습니다. `Future.timeout`은 처리 취소가 아니며 네이티브 호출이 멈추면 `close()`도 지연될 수 있습니다.

## 크기와 인코딩 정책

| API | 의미 |
|---|---|
| `Resize.exact(width:, height:)` | 지정 크기로 변환. 종횡비가 다르면 왜곡을 허용합니다. |
| `Resize.inside(maxWidth:, maxHeight:)` | 적어도 한 경계 안에 맞춥니다. 기본적으로 확대하지 않습니다. |
| `Resize.cover(width:, height:)` | 균일 배율과 중앙 crop으로 지정 크기를 채웁니다. 소수 좌표 영역을 사용합니다. |
| `Crop(x:, y:, width:, height:)` | 직전 결과의 정수 픽셀 영역. 경계 밖이면 실패합니다. |
| `Rotate.clockwise90/180/270` | 시계 방향 회전. |
| `Flip.horizontal/vertical` | 좌우/상하 반전. |
| `JpegEncoding(quality: 90)` | 1..100. 비불투명 알파가 남아 있으면 실패합니다. |
| `const PngEncoding()` | 변환된 픽셀을 PNG로 인코딩합니다. |
| `const WebpLosslessEncoding()` | 변환된 픽셀을 무손실 WebP로 인코딩합니다. |

Resize의 기본 필터는 `ResizeFilter.lanczos3`이며 `triangle`도 제공합니다. exact/cover는 기본 확대 허용입니다. `allowUpscale: false`인데 확대가 필요하면 실패하고, 작은 결과로 대체하지 않습니다. inside는 정수 출력 크기를 내림하고 각 축을 최소 1픽셀로 제한합니다.

작업은 목록 순서대로 적용합니다. crop 바로 뒤의 resize는 자르기 버퍼 복사를 생략하며, 자른 영역을 필터 경계로 유지합니다. 입력과 출력의 FFI 복사 자체는 남아 있습니다.

## 품질·자원·오류

- 인코딩된 색상값과 알파를 직접 계산합니다. 선형광 변환이나 알파 사전 곱셈은 하지 않으므로 투명 경계에 색 번짐이 발생할 수 있습니다.
- 애니메이션을 거부합니다. grayscale/16-bit 자동 변환, EXIF 방향 자동 적용, ICC 색상 관리, 메타데이터 보존은 지원하지 않습니다.
- JPEG는 비불투명 알파를 거부합니다. 모든 알파가 255인 RGBA는 RGB로 변환합니다. 배경색 합성은 하지 않습니다.
- RGB8 JPEG 품질 90은 4:4:4 샘플링과 이미지별 부호표를 사용합니다. 품질 숫자는 다른 인코더와 같은 결과나 파일 크기를 뜻하지 않습니다.
- 입력은 1..256 MiB, 작업은 최대 64개입니다. 입력 한 축은 최대 16,384픽셀, 입력·중간·출력 이미지는 최대 3,200만 픽셀입니다. 디코더 할당 제한은 256 MiB이며 프로세스 전체 메모리 상한은 아닙니다.
- 잘못된 선언적 인자는 `ArgumentError`, 알려진 실행 실패는 `SlimPixelsException`입니다. `code`로 분기하고 `message`는 파싱하지 마세요. 작업 실패의 `operationIndex`는 0부터 시작합니다.
- VM 메모리 고갈, 프로세스 종료, Rust panic은 복구 가능한 예외로 보장하지 않습니다.

공개 API 계약 (`docs/API.md`)에 타입 목록, 오류 코드, 소유권과 호환성 정책을 정리했습니다.

## 네이티브 배포와 검증

`SlimPixels()`는 ABI 2를 확인합니다. 런타임 경로 생성자는 제공하지 않습니다. build hook이 플랫폼별 두 라이브러리와 `SHA256SUMS.json`을 확인하고 번들링합니다. 네트워크 다운로드는 하지 않습니다.

사용자 지정 번들은 소비자 pubspec의 `hooks.user_defines.slim_pixels.native_directory`로 지정합니다. 해시 검증은 무결성 검사이며 배포자 인증은 아닙니다. CLI는 `dart build cli`로 빌드하고 생성된 `bundle/` 전체를 이동하세요. `dart compile exe`는 build hook을 지원하지 않습니다.

```powershell
./tool/build.ps1
./tool/verify.ps1
```

```sh
bash tool/build-linux.sh
```

Windows 빌드에는 MSVC와 Rust 1.97.1이 필요합니다. CI (`CI.md`), 품질 게이트 (`GATES.md`), 배포 조건 (`docs/DISTRIBUTION.md`), 검증 기록 (`docs/VALIDATION.md`)을 참고하세요. 실제 성능은 입력과 환경에 따라 달라집니다.

## 문서와 라이선스

아래 파일은 저장소와 패키지에 포함되어 있습니다. 공개 저장소 URL이 확정되기 전에는 생성된 API 문서에서 깨지는 상대 링크를 사용하지 않습니다.

- 변경 기록 (`CHANGELOG.md`), 기여 방법 (`CONTRIBUTING.md`)
- MIT (`LICENSE`) — Copyright (c) 2026 Seokhyeon Kim
- 제3자 고지 (`THIRD_PARTY_NOTICES.md`)와 `third_party/`를 바이너리 배포에 함께 포함하세요.
