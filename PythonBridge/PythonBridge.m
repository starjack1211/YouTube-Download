#import "PythonBridge.h"
#import <Python/Python.h>
#import <JavaScriptCore/JavaScriptCore.h>

static NSString *ErrorJSON(NSString *message) {
    NSDictionary *value = @{@"ok": @NO, @"error": @{@"code": @"runtime_error", @"message": message ?: @"Python runtime error"}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static PyObject *SolveJS(PyObject *self, PyObject *args) {
    const char *input, *library, *core;
    if (!PyArg_ParseTuple(args, "sss", &input, &library, &core)) return NULL;
    @autoreleasepool {
        JSContext *context = [[JSContext alloc] init];
        __block NSString *failure = nil;
        context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) { failure = [exception toString]; };
        [context evaluateScript:[NSString stringWithUTF8String:library]];
        [context evaluateScript:@"Object.assign(globalThis, lib);"];
        [context evaluateScript:[NSString stringWithUTF8String:core]];
        context[@"_requestJSON"] = [NSString stringWithUTF8String:input];
        JSValue *value = [context evaluateScript:@"JSON.stringify(jsc(JSON.parse(_requestJSON)))"];
        NSString *output = [value toString];
        if (failure || !output || [value isUndefined]) {
            PyErr_SetString(PyExc_RuntimeError, [(failure ?: @"JavaScriptCore returned no result") UTF8String]);
            return NULL;
        }
        return PyUnicode_FromString([output UTF8String]);
    }
}

static PyMethodDef NativeMethods[] = {
    {"solve", SolveJS, METH_VARARGS, "Run bundled EJS in JavaScriptCore."},
    {NULL, NULL, 0, NULL}
};
static struct PyModuleDef NativeModule = {PyModuleDef_HEAD_INIT, "_iosjs", NULL, -1, NativeMethods};
PyMODINIT_FUNC PyInit__iosjs(void) { return PyModule_Create(&NativeModule); }

static NSString *PythonError(void) {
    PyObject *type = NULL, *value = NULL, *trace = NULL;
    PyErr_Fetch(&type, &value, &trace);
    PyErr_NormalizeException(&type, &value, &trace);
    PyObject *text = value ? PyObject_Str(value) : NULL;
    const char *utf8 = text ? PyUnicode_AsUTF8(text) : NULL;
    NSString *message = utf8 ? [NSString stringWithUTF8String:utf8] : @"Python interpreter error";
    Py_XDECREF(text); Py_XDECREF(type); Py_XDECREF(value); Py_XDECREF(trace);
    return message;
}

NSString *PYRunRequest(NSString *requestJSON, NSString *resourcePath) {
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSLock new]; });
    [lock lock];
    @try {
        if (!Py_IsInitialized()) {
            if (PyImport_AppendInittab("_iosjs", PyInit__iosjs) < 0) return ErrorJSON(@"Cannot register JavaScriptCore bridge");
            PyPreConfig pre;
            PyPreConfig_InitIsolatedConfig(&pre);
            pre.utf8_mode = 1;
            PyStatus status = Py_PreInitialize(&pre);
            if (PyStatus_Exception(status)) return ErrorJSON(@"Cannot preinitialize Python");
            PyConfig config;
            PyConfig_InitIsolatedConfig(&config);
            config.write_bytecode = 0;
            config.buffered_stdio = 0;
            config.install_signal_handlers = 0;
            NSString *home = [resourcePath stringByAppendingPathComponent:@"python"];
            status = PyConfig_SetBytesString(&config, &config.home, home.UTF8String);
            if (!PyStatus_Exception(status)) {
                config.module_search_paths_set = 1;
                NSArray<NSString *> *paths = @[
                    [home stringByAppendingPathComponent:@"lib/python3.13"],
                    [home stringByAppendingPathComponent:@"lib/python3.13/lib-dynload"],
                    [resourcePath stringByAppendingPathComponent:@"python_app"],
                    [resourcePath stringByAppendingPathComponent:@"python_packages"]
                ];
                for (NSString *path in paths) {
                    wchar_t *wide = Py_DecodeLocale(path.UTF8String, NULL);
                    if (!wide) { PyConfig_Clear(&config); return ErrorJSON(@"Cannot decode Python path"); }
                    status = PyWideStringList_Append(&config.module_search_paths, wide);
                    PyMem_RawFree(wide);
                    if (PyStatus_Exception(status)) break;
                }
            }
            if (!PyStatus_Exception(status)) status = Py_InitializeFromConfig(&config);
            NSString *initError = PyStatus_Exception(status)
                ? [NSString stringWithUTF8String:status.err_msg ?: "Python initialization failed"] : nil;
            PyConfig_Clear(&config);
            if (initError) return ErrorJSON(initError);
            PyEval_SaveThread();
        }
        PyGILState_STATE gil = PyGILState_Ensure();
        PyObject *module = PyImport_ImportModule("download_core");
        PyObject *function = module ? PyObject_GetAttrString(module, "run_json") : NULL;
        PyObject *argument = PyUnicode_FromString(requestJSON.UTF8String);
        PyObject *result = function && argument ? PyObject_CallOneArg(function, argument) : NULL;
        NSString *output = nil;
        if (result && PyUnicode_Check(result)) {
            const char *utf8 = PyUnicode_AsUTF8(result);
            if (utf8) output = [NSString stringWithUTF8String:utf8];
        }
        if (!output) output = ErrorJSON(PyErr_Occurred() ? PythonError() : @"Python returned an invalid result");
        Py_XDECREF(result); Py_XDECREF(argument); Py_XDECREF(function); Py_XDECREF(module);
        PyGILState_Release(gil);
        return output;
    } @finally { [lock unlock]; }
}
