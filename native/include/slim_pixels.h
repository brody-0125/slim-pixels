#ifndef SLIM_PIXELS_H
#define SLIM_PIXELS_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
uint32_t slim_abi_version(void);
/* ABI 2: success supplies dimensions and format (1 JPEG, 2 PNG, 3 WebP).
 * Failure leaves output empty; operation is a zero-based index or -1.
 * Status: 2 unsupported input, 3 animation, 4 pixel format, 5 decode,
 * 6 crop, 7 upscale, 8 resource limit, 9 transparency, 10 encode,
 * 11 internal/invalid protocol. All output slots must be valid and disjoint. */
int32_t slim_transform(const uint8_t *input, size_t input_len,
                      const uint8_t *plan, size_t plan_len,
                      uint8_t **output, size_t *output_len,
                      uint32_t *width, uint32_t *height, uint32_t *format,
                      int32_t *operation);
/* Inputs are borrowed. Output slots must be writable and disjoint from inputs.
 * Returns 0: encoded bytes, 1: UTF-8 error, 2: invalid ABI arguments.
 * Free every returned non-null buffer exactly once using its original length.
 * Invalid non-null pointers are caller errors; this API cannot validate them. */
int32_t slim_run(const uint8_t *input, size_t input_len,
                 const uint8_t *plan, size_t plan_len,
                 uint8_t **output, size_t *output_len);
void slim_free(uint8_t *buffer, size_t length);
#ifdef __cplusplus
}
#endif
#endif
