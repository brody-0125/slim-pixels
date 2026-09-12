#ifndef SLIM_PIXELS_H
#define SLIM_PIXELS_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
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
