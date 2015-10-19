#import <UIKit/UIKit.h>
#import "App.h"

#import "fishhook.h"
#import <dlfcn.h>
#import <xpc/xpc.h>

/*
typedef void* xpc_connection_t;
typedef void* xpc_endpoint_t;
typedef void* xpc_object_t;

xpc_connection_t xpc_connection_create_from_endpoint(xpc_endpoint_t endpoint);
xpc_connection_t xpc_connection_create(const char *name, dispatch_queue_t q);
xpc_endpoint_t xpc_endpoint_create(xpc_connection_t);
*/

xpc_endpoint_t endpoint;
xpc_connection_t networkingC;

xpc_connection_t (*xpc_connection_create0)(const char*, dispatch_queue_t);
xpc_connection_t xpc_connection_create1(const char* name, dispatch_queue_t q) {
    NSLog(@"xpc_connection_create %s", name);
    if (strcmp(name, "com.apple.WebKit.Networking") == 0) {
        //networkingC = xpc_connection_create0(name, q);
        networkingC = xpc_connection_create_from_endpoint(endpoint);
        return networkingC;
    }
    return xpc_connection_create0(name, q);
}

void (*xpc_connection_send_message0)(xpc_connection_t, xpc_object_t);
void xpc_connection_send_message1(xpc_connection_t c, xpc_object_t m) {
    if (c == networkingC) {
        NSLog(@"xpc_connection_send_message %@", m);
    }
    xpc_connection_send_message0(c, m);
}

void (*xpc_connection_send_message_with_reply0)(xpc_connection_t, xpc_object_t, dispatch_queue_t, xpc_handler_t);
void xpc_connection_send_message_with_reply1(xpc_connection_t c, xpc_object_t m, dispatch_queue_t q, xpc_handler_t h) {
    if (c == networkingC)
    NSLog(@"xpc_connection_send_message_with_reply %@", m);
    xpc_connection_send_message_with_reply0(c, m, q, h);
}

mach_port_t xpc_dictionary_copy_mach_send(xpc_object_t, const char*);

int main(int argc, char * argv[]) {
    
    @autoreleasepool {
        
        xpc_connection_create0 = dlsym(RTLD_DEFAULT, "xpc_connection_create");
        xpc_connection_send_message0 = dlsym(RTLD_DEFAULT, "xpc_connection_send_message");
        xpc_connection_send_message_with_reply0 = dlsym(RTLD_DEFAULT, "xpc_connection_send_message_with_reply");

        rebind_symbols((struct rebinding[3]){
            {"xpc_connection_create", xpc_connection_create1},
            {"xpc_connection_send_message", xpc_connection_send_message1},
            {"xpc_connection_send_message_with_reply", xpc_connection_send_message_with_reply1}
        }, 3);
        
        //dispatch_queue_t networkQ = dispatch_queue_create("NETWORK", 0);

        xpc_connection_t c = xpc_connection_create0(NULL, 0);
        endpoint = xpc_endpoint_create(c);
        xpc_connection_set_event_handler(c, ^(xpc_object_t peer) {
            assert(xpc_get_type(peer) == XPC_TYPE_CONNECTION);
            //xpc_connection_set_target_queue(peer, networkQ);
            NSLog(@"PEER %@", peer);
            xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
                NSLog(@"INCOMING %@", event);
                
                if (event == XPC_ERROR_CONNECTION_INVALID) {
                    // Peer has gone away.
                    NSLog(@"error %@", event);
                    return;
                }

                if (!strcmp(xpc_dictionary_get_string(event, "message-name"), "bootstrap")) {
                    
                    xpc_object_t reply = xpc_dictionary_create_reply(event);
                    xpc_dictionary_set_string(reply, "message-name", "process-finished-launching");
                    xpc_connection_send_message(xpc_dictionary_get_remote_connection(event), reply);
                    
                    mach_port_t port = xpc_dictionary_copy_mach_send(event, "server-port");

                    NSLog(@"  REPLY  %@", reply);
                    //initializerFunctionPtr(peer, event);
                }
            });
            xpc_connection_resume(peer);
        });
        xpc_connection_resume(c);
        
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([App class]));
    }
}
