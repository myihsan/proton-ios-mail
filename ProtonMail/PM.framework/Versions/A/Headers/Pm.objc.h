// Objective-C API for talking to protonmail.com/GoOpenPGP Go package.
//   gobind -lang=objc protonmail.com/GoOpenPGP
//
// File is generated by gobind. Do not edit.

#ifndef __Pm_H__
#define __Pm_H__

@import Foundation;
#include "Universe.objc.h"


@class PmAddress;
@class PmDecryptSignedVerify;
@class PmEncrypted;
@class PmEncryptedSigned;
@class PmKey;
@class PmOpenPGP;

@interface PmAddress : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
@end

@interface PmDecryptSignedVerify : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
- (NSString*)plaintext;
- (void)setPlaintext:(NSString*)v;
@end

@interface PmEncrypted : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
- (NSData*)dataPacket;
- (void)setDataPacket:(NSData*)v;
- (NSData*)keyPacket;
- (void)setKeyPacket:(NSData*)v;
@end

@interface PmEncryptedSigned : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
- (NSString*)encrypted;
- (void)setEncrypted:(NSString*)v;
- (NSString*)signature;
- (void)setSignature:(NSString*)v;
@end

@interface PmKey : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
@end

@interface PmOpenPGP : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
// skipped method OpenPGP.AddAddress with unsupported parameter or return types

- (BOOL)cleanAddresses;
- (NSString*)encryptMessage:(NSString*)addressID plainText:(NSString*)plainText passphrase:(NSString*)passphrase trim:(BOOL)trim;
- (BOOL)removeAddress:(NSString*)addressID;
@end

FOUNDATION_EXPORT NSString* PmArmor(NSData* input);

FOUNDATION_EXPORT BOOL PmCheckPassphrase(NSString* privateKey, NSString* passphrase);

FOUNDATION_EXPORT NSString* PmEncryptMessageSingleBinKey(NSData* publicKey, NSString* plainText, NSString* privateKey, NSString* passphrase, BOOL trim);

FOUNDATION_EXPORT NSString* PmEncryptMessageSingleKey(NSString* publicKey, NSString* plainText, NSString* privateKey, NSString* passphrase, BOOL trim, NSError** error);

FOUNDATION_EXPORT PmKey* PmGenerateKey(NSString* user_name, NSString* domain, NSString* passphrase, long bits);

FOUNDATION_EXPORT NSString* PmGetKeyFingerprint(NSString* publicKey);

FOUNDATION_EXPORT NSString* PmGetKeyFingerprintBin(NSData* publicKey);

FOUNDATION_EXPORT BOOL PmIsKeyExpired(NSString* publicKey);

FOUNDATION_EXPORT BOOL PmIsKeyExpiredBin(NSData* publicKey);

FOUNDATION_EXPORT NSData* PmUnArmor(NSString* input);

#endif
