wkwvquic: an honest-to-god this'll never work attempt at QUIC for WKWebView
==

QUIC for WKWebView would be great for hybrid apps because the initial 3x RTT for TLS more or less guarantees a shitty experience when launching your app.

Approach
--
Fishhook a bunch of xpc_ initialization calls that the UIProcess uses to setup the NetworkProcess and reroute to local xpc server that has a QUIC implementation.

Current status
--
- 2014-10-20: XPC connection setup intercept and initial XPC exchange works. Unfortunately XPC is only used to negotiate mach ports over which the WebKit uses its own serialized protocol.
- 2015-01-18: Setup appropriate mach ports and serialization of init message working

Next up
--
- Get serialization working better, try to see if the initialization message (2k+) is easy to parse

Future impediments
--
- Fishhook no longer works on iOS 9, because dyld calls are optimized.
- IPC serialization shitload is annoying and probably prone to WebKit changes if we bundle/implement the entire protocol ourselves.
- What QUIC implementation will we use?

Ideas welcome!
