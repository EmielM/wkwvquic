#import "wkwvquic.h"

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <mach/mach.h>

#include "fishhook.h"
#include "xpc/xpc.h"

#define OS(DARWIN) 1

/*#include "IPC/MessageEncoder.h"
#include "IPC/mac/MachPort.h"*/

xpc_connection_t networkConn;

xpc_connection_t (*xpc_connection_create0)(const char*, dispatch_queue_t);
xpc_connection_t xpc_connection_create1(const char* name, dispatch_queue_t q) {
    if (strcmp(name, "com.apple.WebKit.Networking") == 0) {
        NSLog(@"xpc_connection_create com.apple.WebKit.Networking intercept");
        return networkConn;
    }
    return xpc_connection_create0(name, q);
}

mach_port_t xpc_dictionary_copy_mach_send(xpc_object_t, const char*);

static const size_t inlineMessageMaxSize = 4096;
static const size_t receiveBufferSize = inlineMessageMaxSize + MAX_TRAILER_SIZE;

static dispatch_queue_t queue;
static dispatch_queue_t queue2;
static dispatch_source_t source;

// Message flags.
enum {
    MessageBodyIsOutOfLine = 1 << 0
};

void hexDump (char *desc, void *addr, int len);

mach_msg_return_t (*mach_msg0)(mach_msg_header_t* msg, mach_msg_option_t option, mach_msg_size_t send_size, mach_msg_size_t receive_limit, mach_port_t receive_name, mach_msg_timeout_t timeout, mach_port_t notify);

mach_msg_return_t mach_msg1(mach_msg_header_t* msg, mach_msg_option_t option, mach_msg_size_t send_size, mach_msg_size_t receive_limit, mach_port_t receive_name, mach_msg_timeout_t timeout, mach_port_t notify) {
    
    mach_msg_return_t r = mach_msg0(msg, option, send_size, receive_limit, receive_name, timeout, notify);
    
    if (receive_limit > 12 && r == 0) {
        // some code to intercept and inspect msg
        char* p = (char*)msg;
        char* end = p+receive_limit - 10;
        while (p < end) {
            if (memcmp(p, "Initialize", 10) == 0) {
                hexDump("mach receive with 'Initialize'", msg, msg->msgh_size);
                break;
            }
            ++p;
        }
    }
    
    return r;
}


void wkwvquic_init() {
    xpc_connection_create0 = (xpc_connection_t (*)(const char*, dispatch_queue_t))dlsym(RTLD_DEFAULT, "xpc_connection_create");
    mach_msg0 = (mach_msg_return_t (*)(mach_msg_header_t*, mach_msg_option_t, mach_msg_size_t, mach_msg_size_t, mach_port_t, mach_msg_timeout_t, mach_port_t))dlsym(RTLD_DEFAULT, "mach_msg");
    rebind_symbols((struct rebinding[2]){
        {"xpc_connection_create", (void *)xpc_connection_create1},
        {"mach_msg", (void*)mach_msg1}
    }, 2);
    

    queue = dispatch_queue_create("com.example.MyQueue", NULL);
    
    // create a networkConn <-> uiConn pipe, where networkConn will be returned by intercepting the right xpc_connection_create, and we will handle events at uiConn
    xpc_connection_t uiConn = xpc_connection_create0(NULL, queue);
    networkConn = xpc_connection_create_from_endpoint(xpc_endpoint_create(uiConn));
    
    xpc_handler_t xpc_event = ^(xpc_object_t event) {
        if (event == XPC_ERROR_CONNECTION_INVALID) {
            NSLog(@"wkwvquic error %@", event);
            return;
        }
        
        NSLog(@"wkwvquic xpc message %@", event);
        
        if (strcmp(xpc_dictionary_get_string(event, "message-name"), "bootstrap")) {
            return;
        }
        
        xpc_object_t reply = xpc_dictionary_create_reply(event);
        xpc_dictionary_set_string(reply, "message-name", "process-finished-launching");
        xpc_connection_send_message(xpc_dictionary_get_remote_connection(event), reply);
        
        mach_port_t sendPort = xpc_dictionary_copy_mach_send(event, "server-port");
        
        mach_port_t receivePort;
        mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &receivePort);
        
        NSLog(@"sendPort=%d receivePort=%d", sendPort, receivePort);
        
        source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, receivePort, 0, queue);
        
        dispatch_source_set_event_handler(source, ^{
            NSLog(@"port event");
            char stackBuffer[receiveBufferSize];
            char* buffer = &stackBuffer[0];
            
            mach_msg_header_t* header = reinterpret_cast<mach_msg_header_t*>(buffer);
            kern_return_t kr = mach_msg(header, MACH_RCV_MSG | MACH_RCV_LARGE | MACH_RCV_TIMEOUT, 0, receiveBufferSize, receivePort, 0, MACH_PORT_NULL);
            if (kr != KERN_SUCCESS) {
                NSLog(@"wtf kr=%d", kr);
                return;
            }
            
            hexDump("received msg ", header, header->msgh_size);
        });
        dispatch_resume(source);
        
        mach_port_limits_t portLimits;
        portLimits.mpl_qlimit = MACH_PORT_QLIMIT_LARGE;
        
        mach_port_set_attributes(mach_task_self(), receivePort, MACH_PORT_DENAP_RECEIVER, (mach_port_info_t)0, 0);
        mach_port_set_attributes(mach_task_self(), receivePort, MACH_PORT_LIMITS_INFO, reinterpret_cast<mach_port_info_t>(&portLimits), MACH_PORT_LIMITS_INFO_COUNT);

        //messageReceiverName = "IPC"
        //messageName = "InitializeConnection"
        
        // send init message
        char msg[] = {
            0x00, // defaultMessageFlags
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 'I','P','C',
            0x00, 0x00, 0x00, 0x00, 0x00, // ??
            0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 'I','n','i','t','i','a','l','i','z','e','C','o','n','n','e','c','t','i','o','n',
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // destinationID
            0x00, 0x00, 0x00, 0x00, //???
            0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22 // UUID
        };
        
        // encoding of the above is still not fully understood: they alignment around the strings is weird..
        // encoding magic starts in StringReference: https://github.com/WebKit/webkit/blob/fb1e48/Source/WebKit2/Platform/IPC/StringReference.h
        // > delegate to DataReference
        // > delegate to SimpleArgumentEncoder
        
        // https://github.com/WebKit/webkit/blob/fb1e4819c96c64af78aa7dd9e4a94756e83d4f08/Source/WebKit2/Platform/IPC/ArgumentCoders.cpp
        
        
        size_t size = round_msg(sizeof(mach_msg_header_t) + sizeof(mach_msg_body_t) + sizeof(msg) + (1 * sizeof(mach_msg_port_descriptor_t)));
        
        char stackBuffer[size];
        char* buffer = &stackBuffer[0];
        memset(buffer, 0, size); // this does not happen in the WebKit code, but would corrupt the message; is there a compiler flag?

        mach_msg_header_t* header = reinterpret_cast<mach_msg_header_t*>(buffer);
        header->msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
        header->msgh_size = size;
        header->msgh_remote_port = sendPort;
        header->msgh_local_port = MACH_PORT_NULL;
        header->msgh_id = 0;

        header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
        
        mach_msg_body_t* body = reinterpret_cast<mach_msg_body_t*>(header + 1);
        body->msgh_descriptor_count = 1;

        mach_msg_descriptor_t* descriptor = reinterpret_cast<mach_msg_descriptor_t*>(body + 1);
        descriptor->port.name = receivePort;
        descriptor->port.disposition = MACH_MSG_TYPE_MAKE_SEND;
        descriptor->port.type = MACH_MSG_PORT_DESCRIPTOR;
        
        memcpy(reinterpret_cast<void*>(descriptor+1), msg, sizeof(msg));
        
        kern_return_t kr = mach_msg(header, MACH_SEND_MSG, size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        NSLog(@"sent mach message size=%zu kr=%d", size, kr);

    };
    
    xpc_connection_set_event_handler(uiConn, ^(xpc_object_t peer) {
        assert(xpc_get_type(peer) == XPC_TYPE_CONNECTION);
        xpc_connection_set_target_queue(peer, queue);
        NSLog(@"wkwvquic xpc connection from %@", peer);
        xpc_connection_set_event_handler(peer, xpc_event);
        xpc_connection_resume(peer);
    });
    xpc_connection_resume(uiConn);
    
    NSLog(@"init done!");

}


void hexDump (char *desc, void *addr, int len) {
    int i;
    unsigned char buff[17];
    unsigned char *pc = (unsigned char*)addr;
    
    // Output description if given.
    if (desc != NULL)
        printf ("%s:\n", desc);
    
    // Process every byte in the data.
    for (i = 0; i < len; i++) {
        // Multiple of 16 means new line (with line offset).
        
        if ((i % 16) == 0) {
            // Just don't print ASCII for the zeroth line.
            if (i != 0)
                printf ("  %s\n", buff);
            
            // Output the offset.
            printf ("  %04x ", i);
        }
        
        // Now the hex code for the specific character.
        printf (" %02x", pc[i]);
        
        // And store a printable ASCII character for later.
        if ((pc[i] < 0x20) || (pc[i] > 0x7e))
            buff[i % 16] = '.';
        else
            buff[i % 16] = pc[i];
        buff[(i % 16) + 1] = '\0';
    }
    
    // Pad out last line if not exactly 16 characters.
    while ((i % 16) != 0) {
        printf ("   ");
        i++;
    }
    
    // And print the final ASCII bit.
    printf ("  %s\n", buff);
}


void wkwvquic_encode() {
    // https://github.com/WebKit/webkit/blob/fb1e4819c96c64af78aa7dd9e4a94756e83d4f08/Source/WebKit2/Platform/IPC/mac/ConnectionMac.mm#L268
}