#include "pt.h"
long pt_sum(struct pt *x) { return x->c + x->l + (long)x->d + (x->p == NULL); }
void pt_fill(struct pt *x) { x->c = 'z'; x->l = -42; x->p = x; x->d = 2.25; }
size_t pt_size(void) { return sizeof(struct pt); }
