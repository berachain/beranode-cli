/*
 * Security.h — Minimal stub for cross-compiling Go/CGO to darwin-arm64.
 *
 * Provides type declarations and function signatures used by go-keychain
 * (github.com/99designs/go-keychain) and related Cosmos SDK keyring packages.
 * Actual implementations are resolved at link time via Zig's macOS TBD stubs.
 */
#ifndef __SECURITY_SECURITY_H__
#define __SECURITY_SECURITY_H__

#include <CoreFoundation/CoreFoundation.h>

/* ── Keychain opaque types ───────────────────────────────────────────── */
/* uintptr_t so these convert to CFTypeRef and accept 0 (see CoreFoundation.h). */
typedef uintptr_t SecKeychainItemRef;
typedef uintptr_t SecKeychainRef;
typedef uintptr_t SecAccessRef;
typedef uintptr_t SecTrustedApplicationRef;
typedef UInt32    SecKeychainStatus;

/* ── SecItem CRUD operations ─────────────────────────────────────────── */
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result);
OSStatus SecItemDelete(CFDictionaryRef query);
OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);

/* ── Keychain management ─────────────────────────────────────────────── */
OSStatus SecKeychainOpen(const char *pathName, SecKeychainRef *keychain);
OSStatus SecKeychainCopyDefault(SecKeychainRef *keychain);
OSStatus SecKeychainCreate(const char *pathName, UInt32 passwordLength, const void *password, Boolean promptUser, SecAccessRef initialAccess, SecKeychainRef *keychain);
OSStatus SecKeychainDelete(SecKeychainRef keychainOrArray);
OSStatus SecKeychainSetSearchList(CFArrayRef searchList);
OSStatus SecKeychainGetStatus(SecKeychainRef keychain, SecKeychainStatus *keychainStatus);
OSStatus SecKeychainLock(SecKeychainRef keychain);
OSStatus SecKeychainUnlock(SecKeychainRef keychain, UInt32 passwordLength, const void *password, Boolean usePassword);
OSStatus SecKeychainItemDelete(SecKeychainItemRef itemRef);

/* ── Access control ──────────────────────────────────────────────────── */
OSStatus SecAccessCreate(CFStringRef descriptor, CFArrayRef trustedlist, SecAccessRef *accessRef);
OSStatus SecTrustedApplicationCreateFromPath(const char *path, SecTrustedApplicationRef *app);

/* ── Item class constants ────────────────────────────────────────────── */
extern const CFStringRef kSecClass;
extern const CFStringRef kSecClassGenericPassword;
extern const CFStringRef kSecClassInternetPassword;
extern const CFStringRef kSecClassCertificate;
extern const CFStringRef kSecClassKey;
extern const CFStringRef kSecClassIdentity;

/* ── Item attribute constants ────────────────────────────────────────── */
extern const CFStringRef kSecAttrService;
extern const CFStringRef kSecAttrAccount;
extern const CFStringRef kSecAttrLabel;
extern const CFStringRef kSecAttrAccess;
extern const CFStringRef kSecAttrAccessGroup;
extern const CFStringRef kSecAttrAccessible;
extern const CFStringRef kSecAttrSynchronizable;
extern const CFStringRef kSecAttrDescription;
extern const CFStringRef kSecAttrComment;
extern const CFStringRef kSecAttrCreator;
extern const CFStringRef kSecAttrType;
extern const CFStringRef kSecAttrServer;
extern const CFStringRef kSecAttrProtocol;
extern const CFStringRef kSecAttrPort;
extern const CFStringRef kSecAttrPath;
extern const CFStringRef kSecAttrCreationDate;
extern const CFStringRef kSecAttrModificationDate;

/* ── Accessibility constants ─────────────────────────────────────────── */
extern const CFStringRef kSecAttrAccessibleWhenUnlocked;
extern const CFStringRef kSecAttrAccessibleAfterFirstUnlock;
extern const CFStringRef kSecAttrAccessibleAlways;
extern const CFStringRef kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly;
extern const CFStringRef kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
extern const CFStringRef kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
extern const CFStringRef kSecAttrAccessibleAlwaysThisDeviceOnly;

/* ── Synchronizable ──────────────────────────────────────────────────── */
extern const CFStringRef kSecAttrSynchronizableAny;

/* ── Search / return attributes ──────────────────────────────────────── */
extern const CFStringRef kSecMatchLimit;
extern const CFStringRef kSecMatchLimitOne;
extern const CFStringRef kSecMatchLimitAll;
extern const CFStringRef kSecMatchSearchList;
extern const CFStringRef kSecReturnData;
extern const CFStringRef kSecReturnAttributes;
extern const CFStringRef kSecReturnRef;
extern const CFStringRef kSecReturnPersistentRef;
extern const CFStringRef kSecValueData;
extern const CFStringRef kSecValueRef;

/* ── Keychain use attribute ──────────────────────────────────────────── */
extern const CFStringRef kSecUseKeychain;

/* ── Error codes ─────────────────────────────────────────────────────── */
enum {
    errSecSuccess                = 0,
    errSecUnimplemented          = -4,
    errSecParam                  = -50,
    errSecAllocate               = -108,
    errSecNotAvailable           = -25291,
    errSecAuthFailed             = -25293,
    errSecNoSuchKeychain         = -25294,
    errSecDuplicateItem          = -25299,
    errSecItemNotFound           = -25300,
    errSecInteractionNotAllowed  = -25308,
    errSecNoAccessForItem        = -25243,
    errSecDecode                 = -26275,
    errSecBadReq                 = -909
};

#endif /* __SECURITY_SECURITY_H__ */
