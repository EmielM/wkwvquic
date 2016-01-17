#include "xpc/xpc.h"

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

void wkwvquic_init();
mach_port_t xpc_dictionary_copy_mach_send(xpc_object_t, const char*);
    
#ifdef __cplusplus
}
#endif //__cplusplus
