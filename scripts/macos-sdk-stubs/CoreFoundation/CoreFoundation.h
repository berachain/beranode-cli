/*
 * CoreFoundation.h — Minimal stub for cross-compiling Go/CGO to darwin-arm64.
 *
 * Provides type declarations and function signatures used by go-keychain
 * (github.com/99designs/go-keychain) and related Cosmos SDK keyring packages.
 * Actual implementations are resolved at link time via Zig's macOS TBD stubs.
 */
#ifndef __COREFOUNDATION_COREFOUNDATION_H__
#define __COREFOUNDATION_COREFOUNDATION_H__

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

/* ── Basic scalar types ──────────────────────────────────────────────── */
typedef unsigned char           Boolean;
typedef unsigned char           UInt8;
typedef int8_t                  SInt8;
typedef int16_t                 SInt16;
typedef int32_t                 SInt32;
typedef int64_t                 SInt64;
typedef uint32_t                UInt32;
typedef float                   Float32;
typedef double                  Float64;
typedef int32_t                 OSStatus;
typedef signed long             CFIndex;
typedef unsigned long           CFTypeID;
typedef unsigned long           CFOptionFlags;
typedef unsigned long           CFHashCode;

/*
 * Opaque CF types must be uintptr_t.
 *
 * Real Apple headers use pointers, but go-keychain (and cgo on Darwin)
 * treats CFTypeRef / CFStringRef / Sec*Ref as uintptr: it compares them
 * to 0, returns 0, and converts freely between them. Pointer typedefs
 * make those operations illegal in Go. uintptr_t is ABI-compatible with
 * pointers on darwin-arm64 (both 8 bytes, passed in the same register).
 */
typedef uintptr_t CFTypeRef;
typedef uintptr_t CFAllocatorRef;
typedef uintptr_t CFStringRef;
typedef uintptr_t CFMutableStringRef;
typedef uintptr_t CFDataRef;
typedef uintptr_t CFMutableDataRef;
typedef uintptr_t CFDictionaryRef;
typedef uintptr_t CFMutableDictionaryRef;
typedef uintptr_t CFArrayRef;
typedef uintptr_t CFMutableArrayRef;
typedef uintptr_t CFBooleanRef;
typedef uintptr_t CFNumberRef;
typedef uintptr_t CFDateRef;
typedef uintptr_t CFErrorRef;

/* ── CFRange ─────────────────────────────────────────────────────────── */
typedef struct {
    CFIndex location;
    CFIndex length;
} CFRange;

/* ── Date / time ─────────────────────────────────────────────────────── */
typedef double CFTimeInterval;
typedef CFTimeInterval CFAbsoluteTime;
extern const CFTimeInterval kCFAbsoluteTimeIntervalSince1970;
CFDateRef      CFDateCreate(CFAllocatorRef allocator, CFAbsoluteTime at);
CFAbsoluteTime CFDateGetAbsoluteTime(CFDateRef theDate);

/* ── Allocator constants ─────────────────────────────────────────────── */
extern const CFAllocatorRef kCFAllocatorDefault;
extern const CFAllocatorRef kCFAllocatorSystemDefault;
extern const CFAllocatorRef kCFAllocatorMalloc;
extern const CFAllocatorRef kCFAllocatorNull;

/* ── Boolean constants ───────────────────────────────────────────────── */
extern const CFBooleanRef kCFBooleanTrue;
extern const CFBooleanRef kCFBooleanFalse;
Boolean CFBooleanGetValue(CFBooleanRef boolean);

/* ── String encoding ─────────────────────────────────────────────────── */
typedef uint32_t CFStringEncoding;
enum {
    kCFStringEncodingMacRoman      = 0,
    kCFStringEncodingUTF8          = 0x08000100,
    kCFStringEncodingASCII         = 0x0600
};

/* ── CFString functions ──────────────────────────────────────────────── */
CFStringRef  CFStringCreateWithCString(CFAllocatorRef alloc, const char *cStr, CFStringEncoding encoding);
CFStringRef  CFStringCreateWithBytes(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes, CFStringEncoding encoding, Boolean isExternalRepresentation);
CFIndex      CFStringGetLength(CFStringRef theString);
Boolean      CFStringGetCString(CFStringRef theString, char *buffer, CFIndex bufferSize, CFStringEncoding encoding);
CFIndex      CFStringGetMaximumSizeForEncoding(CFIndex length, CFStringEncoding encoding);
const char * CFStringGetCStringPtr(CFStringRef theString, CFStringEncoding encoding);
CFIndex      CFStringGetBytes(CFStringRef theString, CFRange range, CFStringEncoding encoding, UInt8 lossByte, Boolean isExternalRepresentation, UInt8 *buffer, CFIndex maxBufLen, CFIndex *usedBufLen);

/* ── CFData functions ────────────────────────────────────────────────── */
CFDataRef    CFDataCreate(CFAllocatorRef allocator, const UInt8 *bytes, CFIndex length);
const UInt8 *CFDataGetBytePtr(CFDataRef theData);
CFIndex      CFDataGetLength(CFDataRef theData);

/* ── CFDictionary callbacks ──────────────────────────────────────────── */
typedef const void *(*CFDictionaryRetainCallBack)(CFAllocatorRef allocator, const void *value);
typedef void        (*CFDictionaryReleaseCallBack)(CFAllocatorRef allocator, const void *value);
typedef CFStringRef (*CFDictionaryCopyDescriptionCallBack)(const void *value);
typedef Boolean     (*CFDictionaryEqualCallBack)(const void *value1, const void *value2);
typedef CFHashCode  (*CFDictionaryHashCallBack)(const void *value);

typedef struct {
    CFIndex                             version;
    CFDictionaryRetainCallBack          retain;
    CFDictionaryReleaseCallBack         release;
    CFDictionaryCopyDescriptionCallBack copyDescription;
    CFDictionaryEqualCallBack           equal;
    CFDictionaryHashCallBack            hash;
} CFDictionaryKeyCallBacks;

typedef struct {
    CFIndex                             version;
    CFDictionaryRetainCallBack          retain;
    CFDictionaryReleaseCallBack         release;
    CFDictionaryCopyDescriptionCallBack copyDescription;
    CFDictionaryEqualCallBack           equal;
} CFDictionaryValueCallBacks;

extern const CFDictionaryKeyCallBacks   kCFTypeDictionaryKeyCallBacks;
extern const CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks;

/* ── CFDictionary functions ──────────────────────────────────────────── */
CFDictionaryRef        CFDictionaryCreate(CFAllocatorRef allocator, const void **keys, const void **values, CFIndex numValues, const CFDictionaryKeyCallBacks *keyCallBacks, const CFDictionaryValueCallBacks *valueCallBacks);
CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef allocator, CFIndex capacity, const CFDictionaryKeyCallBacks *keyCallBacks, const CFDictionaryValueCallBacks *valueCallBacks);
void                   CFDictionarySetValue(CFMutableDictionaryRef theDict, const void *key, const void *value);
const void *           CFDictionaryGetValue(CFDictionaryRef theDict, const void *key);
CFIndex                CFDictionaryGetCount(CFDictionaryRef theDict);
Boolean                CFDictionaryContainsKey(CFDictionaryRef theDict, const void *key);
void                   CFDictionaryGetKeysAndValues(CFDictionaryRef theDict, const void **keys, const void **values);

/* ── CFArray callbacks ───────────────────────────────────────────────── */
typedef const void *(*CFArrayRetainCallBack)(CFAllocatorRef allocator, const void *value);
typedef void        (*CFArrayReleaseCallBack)(CFAllocatorRef allocator, const void *value);
typedef CFStringRef (*CFArrayCopyDescriptionCallBack)(const void *value);
typedef Boolean     (*CFArrayEqualCallBack)(const void *value1, const void *value2);

typedef struct {
    CFIndex                         version;
    CFArrayRetainCallBack           retain;
    CFArrayReleaseCallBack          release;
    CFArrayCopyDescriptionCallBack  copyDescription;
    CFArrayEqualCallBack            equal;
} CFArrayCallBacks;

extern const CFArrayCallBacks kCFTypeArrayCallBacks;

/* ── CFArray functions ───────────────────────────────────────────────── */
CFArrayRef   CFArrayCreate(CFAllocatorRef allocator, const void **values, CFIndex numValues, const CFArrayCallBacks *callBacks);
CFIndex      CFArrayGetCount(CFArrayRef theArray);
const void * CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx);
void         CFArrayGetValues(CFArrayRef theArray, CFRange range, const void **values);

/* ── CFNumber ────────────────────────────────────────────────────────── */
typedef enum {
    kCFNumberSInt8Type      = 1,
    kCFNumberSInt16Type     = 2,
    kCFNumberSInt32Type     = 3,
    kCFNumberSInt64Type     = 4,
    kCFNumberFloat32Type    = 5,
    kCFNumberFloat64Type    = 6,
    kCFNumberCharType       = 7,
    kCFNumberShortType      = 8,
    kCFNumberIntType        = 9,
    kCFNumberLongType       = 10,
    kCFNumberLongLongType   = 11,
    kCFNumberFloatType      = 12,
    kCFNumberDoubleType     = 13,
    kCFNumberCFIndexType    = 14,
    kCFNumberNSIntegerType  = 15,
    kCFNumberCGFloatType    = 16
} CFNumberType;

CFNumberRef    CFNumberCreate(CFAllocatorRef allocator, CFNumberType theType, const void *valuePtr);
Boolean        CFNumberGetValue(CFNumberRef number, CFNumberType theType, void *valuePtr);
CFNumberType   CFNumberGetType(CFNumberRef number);

/* ── Type IDs ────────────────────────────────────────────────────────── */
CFTypeID    CFGetTypeID(CFTypeRef cf);
CFTypeID    CFArrayGetTypeID(void);
CFTypeID    CFBooleanGetTypeID(void);
CFTypeID    CFDataGetTypeID(void);
CFTypeID    CFDateGetTypeID(void);
CFTypeID    CFDictionaryGetTypeID(void);
CFTypeID    CFNumberGetTypeID(void);
CFTypeID    CFStringGetTypeID(void);
CFStringRef CFCopyTypeIDDescription(CFTypeID type_id);

/* ── Memory management ───────────────────────────────────────────────── */
CFTypeRef CFRetain(CFTypeRef cf);
void      CFRelease(CFTypeRef cf);

/* ── CFError ─────────────────────────────────────────────────────────── */
CFStringRef CFErrorCopyDescription(CFErrorRef err);

#endif /* __COREFOUNDATION_COREFOUNDATION_H__ */
