#include <stddef.h>
/* fields whose offsets differ between LP64 and wasm32 */
struct pt { char c; long l; void *p; double d; };
long pt_sum(struct pt *x);
void pt_fill(struct pt *x);
size_t pt_size(void);
