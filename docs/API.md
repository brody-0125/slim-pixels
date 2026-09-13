# 공개 API 계약

ABI 2 기반의 현재 작업 트리 계약입니다. 지원 범위와 실행 예시는 [README](../README.md), 이행 기록은 [CHANGELOG](../CHANGELOG.md)를 참고하세요.

## 진입점과 타입

```dart
ImageResult transformSync(
  Uint8List input, {
  List<ImageOperation> operations = const [],
  required ImageEncoding encoding,
});
```

위 메서드는 `SlimPixels()`의 인스턴스 메서드입니다. 인스턴스는 isolate별 네이티브 초기화를 공유하고 가변 처리 설정은 갖지 않습니다. 클라이언트를 다른 isolate로 전달하지 말고 worker 안에서 생성합니다.

| 타입 | 공개 구성 |
|---|---|
| SlimPixelsWorker | start(maxPendingRequests: 4, maxPendingInputBytes: 268435456), transform(input, operations:, required encoding:), close() |
| ImageOperation | abstract final. 외부 구현/상속 금지 |
| Resize | exact/cover(width, height), inside(maxWidth?, maxHeight?). 모두 named parameter. filter, allowUpscale 옵션; 읽기 속성 filter, allowsUpscale |
| Crop | named x/y/width/height와 동일한 읽기 속성 |
| Rotate | clockwise90, clockwise180, clockwise270 |
| Flip | horizontal, vertical |
| ResizeFilter | lanczos3, triangle 상수와 name |
| ImageEncoding | abstract final. 외부 구현/상속 금지 |
| JpegEncoding | quality 기본 90, 범위 1..100 |
| PngEncoding / WebpLosslessEncoding | const 무인자 생성자 |
| ImageResult | private 생성자; bytes, width, height, format, mimeType, byteLength |
| ImageFormat | jpeg/png/webp 상수, name, mimeType |
| SlimPixelsException | private 생성자; code, message, operationIndex |
| SlimPixelsErrorCode | 아래 상수와 name |

기하 작업은 검증된 값만 저장합니다. 크기는 1..4294967295, crop 좌표는 0..4294967295입니다. 이는 정수 표현 범위이며 실제 처리 자원 제한은 별도로 적용합니다. 입력 내용에 의존하는 검증은 decode 이후 작업 순서대로 수행합니다.

## 기하학

inside는 제공된 경계 비율의 최솟값을 사용하고, 확대 금지면 배율을 최대 1로 제한합니다. 정수 곱셈/나눗셈으로 크기를 내림하며 각 축은 최소 1입니다. 따라서 정수 격자의 비율 오차는 있을 수 있습니다.

cover는 입력 w×h, 출력 W×H에 대해 s=max(W/w,H/h), crop 영역 W/s×H/s를 중심에 놓습니다. 소수 좌표를 정수로 버리지 않습니다. exact는 각각의 축을 지정 크기로 변환합니다. exact/cover의 확대 금지 실패 코드는 upscaleRequired입니다.

crop의 영역은 [x,x+width)×[y,y+height)입니다. 자동 clamp하지 않습니다. crop→resize 최적화도 동일 경계를 유지합니다. 연속 resize를 임의로 합치지 않습니다.

## 실패 계약

| code | 의미 |
|---|---|
| workerStartFailed | isolate 생성 인프라 실패 |
| workerCapacityExceeded | 실행 중 + 대기 입력 개수/바이트 한도 초과 |
| workerTerminated | 예기치 않은 worker 오류 또는 종료 |
| nativeUnavailable | 런타임 로딩 또는 심볼 해석 실패 |
| incompatibleNative | ABI 불일치 |
| unsupportedInput | 지원하지 않는 컨테이너 |
| animatedInputUnsupported | 애니메이션 입력 |
| unsupportedPixelFormat | 지원하지 않는 디코딩 색 타입/비트 깊이 |
| decodeFailed | 지원 포맷의 디코딩 실패 |
| cropOutOfBounds | 현재 이미지 밖 crop |
| upscaleRequired | 금지된 확대 필요 |
| resourceLimitExceeded | 처리 자원 제한 초과 |
| transparencyUnsupported | JPEG 인코딩 시 비불투명 알파 |
| encodeFailed | 인코딩 실패 |
| internalFailure | 내부 요청/응답 프로토콜 오류 |

operationIndex는 사용자 작업 목록의 0-based 위치이며 그 외 단계는 null입니다. native 오류 문자열이나 외부 예외 객체는 공개하지 않습니다. 알려진 로딩 오류가 SDK의 ArgumentError인 경우 로더 호출 경계에서만 변환합니다. 일반 프로그래밍 Error를 일괄 포장하지 않습니다. build hook 실패는 빌드 오류입니다.

예외 코드는 추가될 수 있으므로 기본 실패 처리도 작성하세요. 결과 포맷/필터는 확장 가능한 상수 객체이며 exhaustive enum이 아닙니다. Rotate/Flip의 열거값은 고정입니다. 작업/결과에 deep equality를 약속하지 않습니다.

## 소유권과 의미

입력은 동기 호출 중 읽고 수정·보관하지 않습니다. 네이티브 입력 복사와 결과 복사는 존재합니다. 결과를 Dart로 복사한 뒤 네이티브 버퍼는 finally에서 해제합니다. 반환 바이트의 직접 쓰기·buffer view·sublist view 쓰기는 금지됩니다. 수정은 명시적으로 복사해서 수행합니다.

빈 작업 목록도 decode→encode합니다. EXIF 방향을 적용하지 않고 메타데이터도 보존하지 않습니다. PNG/무손실 WebP라는 명칭은 인코딩 단계에만 해당합니다. resize는 encoded-color/straight-alpha 규칙을 유지합니다. 버전·플랫폼을 초월한 바이트 동일성은 계약하지 않습니다.

## 기존 호출에서 이행

- `transform(bytes, map)` → `transformSync(bytes, operations: [...], encoding: ...)`.
- 반환 Uint8List → ImageResult.bytes와 네이티브 출력 메타데이터.
- `SlimPixels(path)` → `SlimPixels()` 및 빌드 시 native_directory 설정.
- 공개 scalar/JSON 옵션 삭제. 비교 실험의 raw ABI 호출은 배포에서 제외한 tool/validation 안에만 유지합니다.
- 투명 JPEG 12개 기존 회귀 사례는 성공 출력 대신 transparencyUnsupported를 검사합니다. 기존 golden 이미지는 변경하지 않았습니다.

현재 자동 검증 범위와 미검증 실패 주입은 [검증 기록](VALIDATION.md)을 확인하세요. 타입 계약만으로 메모리 고갈·모든 코덱 결함의 복구를 보장하지 않습니다.

## Worker 수명과 소유권

`await SlimPixelsWorker.start()`는 worker 안의 네이티브 초기화까지 기다립니다. 동기 API와 동일한 타입·변환·오류 코드를 사용하며 ABI는 2로 유지됩니다. 초기화 실패의 nativeUnavailable/incompatibleNative는 그대로 전달합니다. build hook 실패는 비동기 예외가 아닌 빌드 오류입니다.

transform은 호출 중 입력을 TransferableTypedData로 복사하고 작업 목록을 별도로 복사합니다. 오류는 반환 Future로 전달합니다. 타입 값 생성자의 ArgumentError는 생성 시 발생합니다. 인자 검증은 동기 API와 공유합니다. 한도는 실행 중과 대기 중 입력에 적용하며 결과 보관량이나 디코딩 버퍼까지 합친 메모리 상한이 아닙니다.

close는 즉시 신규 제출을 막고 FIFO를 비운 후 isolate 종료를 기다립니다. 여러 close는 동일 Future를 반환합니다. 종료 중/종료 후 제출은 StateError, 종료 전 실패 상태의 제출은 workerTerminated입니다. 일반 SlimPixelsException은 해당 요청만 실패시킵니다. 비정상 종료는 모든 대기 Future를 완료하고 예약량을 해제합니다. 자동 재시도·pool·cancel·우선순위는 제공하지 않습니다. OS 네이티브 라이브러리 unload나 native crash 격리는 보장하지 않습니다.
