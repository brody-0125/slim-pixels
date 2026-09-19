# Third-party notices

This software is based in part on the work of the Independent JPEG Group.

TurboJPEG 3.2.0 build 20260805 is supplied as a Windows x64 DLL from the local runtime distribution. SHA256: `D1595894A7EBA70DE1B2FCE771BA311FE6D13175395DB4F7D2BA5703F26E28BF`. Its original compiler flags are not recorded; this is not a reproducible-from-source binary claim. See `third_party/libjpeg-turbo/`.

The table covers Cargo resolved dependencies (including optional/target-specific entries, not a claim that every package is linked) and the Dart runtime dependency. License texts are copied unmodified from the resolved local package sources. For zune-core/zune-jpeg, the copyright notice comes from the exact upstream commit recorded in the crate's .cargo_vcs_info.json (see SOURCE.txt), accompanied by the Apache 2.0 license text.

| Package | License expression | Texts |
|---|---|---|
| adler2-2.0.1 | 0BSD OR MIT OR Apache-2.0 | third_party/rust/adler2-2.0.1/ |
| autocfg-1.5.0 | Apache-2.0 OR MIT | third_party/rust/autocfg-1.5.0/ |
| bitflags-2.10.0 | MIT OR Apache-2.0 | third_party/rust/bitflags-2.10.0/ |
| bytemuck-1.25.2 | Zlib OR Apache-2.0 OR MIT | third_party/rust/bytemuck-1.25.2/ |
| byteorder-lite-0.1.0 | Unlicense OR MIT | third_party/rust/byteorder-lite-0.1.0/ |
| cfg-if-1.0.4 | MIT OR Apache-2.0 | third_party/rust/cfg-if-1.0.4/ |
| crc32fast-1.5.0 | MIT OR Apache-2.0 | third_party/rust/crc32fast-1.5.0/ |
| document-features-0.2.12 | MIT OR Apache-2.0 | third_party/rust/document-features-0.2.12/ |
| fast_image_resize-6.1.0 | MIT OR Apache-2.0 | third_party/rust/fast_image_resize-6.1.0/ |
| fdeflate-0.3.7 | MIT OR Apache-2.0 | third_party/rust/fdeflate-0.3.7/ |
| flate2-1.1.4 | MIT OR Apache-2.0 | third_party/rust/flate2-1.1.4/ |
| image-0.25.8 | MIT OR Apache-2.0 | third_party/rust/image-0.25.8/ |
| image-webp-0.2.4 | MIT OR Apache-2.0 | third_party/rust/image-webp-0.2.4/ |
| itoa-1.0.18 | MIT OR Apache-2.0 | third_party/rust/itoa-1.0.18/ |
| litrs-1.0.0 | MIT OR Apache-2.0 | third_party/rust/litrs-1.0.0/ |
| memchr-2.7.6 | Unlicense OR MIT | third_party/rust/memchr-2.7.6/ |
| miniz_oxide-0.8.9 | MIT OR Zlib OR Apache-2.0 | third_party/rust/miniz_oxide-0.8.9/ |
| moxcms-0.7.7 | BSD-3-Clause OR Apache-2.0 | third_party/rust/moxcms-0.7.7/ |
| num-traits-0.2.19 | MIT OR Apache-2.0 | third_party/rust/num-traits-0.2.19/ |
| png-0.18.0 | MIT OR Apache-2.0 | third_party/rust/png-0.18.0/ |
| proc-macro2-1.0.102 | MIT OR Apache-2.0 | third_party/rust/proc-macro2-1.0.102/ |
| pxfm-0.1.25 | BSD-3-Clause OR Apache-2.0 | third_party/rust/pxfm-0.1.25/ |
| quick-error-2.0.1 | MIT/Apache-2.0 | third_party/rust/quick-error-2.0.1/ |
| quote-1.0.41 | MIT OR Apache-2.0 | third_party/rust/quote-1.0.41/ |
| serde-1.0.228 | MIT OR Apache-2.0 | third_party/rust/serde-1.0.228/ |
| serde_core-1.0.228 | MIT OR Apache-2.0 | third_party/rust/serde_core-1.0.228/ |
| serde_derive-1.0.228 | MIT OR Apache-2.0 | third_party/rust/serde_derive-1.0.228/ |
| serde_json-1.0.151 | MIT OR Apache-2.0 | third_party/rust/serde_json-1.0.151/ |
| simd-adler32-0.3.7 | MIT | third_party/rust/simd-adler32-0.3.7/ |
| syn-2.0.108 | MIT OR Apache-2.0 | third_party/rust/syn-2.0.108/ |
| syn-3.0.5 | MIT OR Apache-2.0 | third_party/rust/syn-3.0.5/ |
| thiserror-2.0.20 | MIT OR Apache-2.0 | third_party/rust/thiserror-2.0.20/ |
| thiserror-impl-2.0.20 | MIT OR Apache-2.0 | third_party/rust/thiserror-impl-2.0.20/ |
| unicode-ident-1.0.20 | (MIT OR Apache-2.0) AND Unicode-3.0 | third_party/rust/unicode-ident-1.0.20/ |
| zmij-1.0.23 | MIT | third_party/rust/zmij-1.0.23/ |
| zune-core-0.4.12 | MIT OR Apache-2.0 OR Zlib | third_party/rust/zune-core-0.4.12/ |
| zune-jpeg-0.4.21 | MIT OR Apache-2.0 OR Zlib | third_party/rust/zune-jpeg-0.4.21/ |
| ffi 2.2.0 | BSD-3-Clause | third_party/dart/ffi/LICENSE |

## Dart build and transitive dependencies

These packages are resolved for the build hook and Dart package. This is not a claim that every dependency is included in the native binary.

- code_assets 2.1.0: `third_party/dart/code_assets/LICENSE`
- collection 1.19.1: `third_party/dart/collection/LICENSE`
- crypto 3.0.7: `third_party/dart/crypto/LICENSE`
- hooks 2.2.0: `third_party/dart/hooks/LICENSE`
- logging 1.3.0: `third_party/dart/logging/LICENSE`
- meta 1.19.0: `third_party/dart/meta/LICENSE`
- path 1.9.1: `third_party/dart/path/LICENSE`
- pub_semver 2.2.1: `third_party/dart/pub_semver/LICENSE`
- record_use 1.1.1: `third_party/dart/record_use/LICENSE`
- source_span 1.10.2: `third_party/dart/source_span/LICENSE`
- string_scanner 1.4.1: `third_party/dart/string_scanner/LICENSE`
- term_glyph 1.2.2: `third_party/dart/term_glyph/LICENSE`
- typed_data 1.4.0: `third_party/dart/typed_data/LICENSE`
- yaml 3.1.4: `third_party/dart/yaml/LICENSE`
