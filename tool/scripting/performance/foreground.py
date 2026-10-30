"""Activate only the benchmark PID using AppKit; never look up by bundle ID.

Activation is requested after first-frame telemetry. Direct
Popen ownership is retained, including deterministic termination on timeout.
"""
import ctypes
import time


def activate_pid(pid, timeout=2):
    if type(pid) is not int or pid <= 0:
        raise ValueError('A positive child process ID is required')
    ctypes.CDLL('/System/Library/Frameworks/AppKit.framework/AppKit')
    objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    selector = objc.sel_registerName
    object_message = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(('objc_msgSend', objc))
    pid_message = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int)(('objc_msgSend', objc))
    flag_message = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong)(('objc_msgSend', objc))
    bool_message = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(('objc_msgSend', objc))
    void_message = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)(('objc_msgSend', objc))
    pool = object_message(objc.objc_getClass(b'NSAutoreleasePool'), selector(b'new'))
    try:
        app = pid_message(objc.objc_getClass(b'NSRunningApplication'), selector(b'runningApplicationWithProcessIdentifier:'), pid)
        if not app:
            return False
        # NSApplicationActivateAllWindows | ActivateIgnoringOtherApps.
        flag_message(app, selector(b'activateWithOptions:'), 3)
        deadline = time.monotonic() + timeout
        while True:
            if bool_message(app, selector(b'isActive')):
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(.02)
    finally:
        void_message(pool, selector(b'drain'))
