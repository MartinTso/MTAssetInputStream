//
//  MTFastAssetReader.m
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.02.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "MTFastAssetReader.h"

static uint64_t const kAssetCacheBufferSize = 131072;

@implementation MTFastAssetReader {
    uint8_t _assetCache[kAssetCacheBufferSize];
    MTLength _assetSize;
    MTLength _assetCacheSize;
    MTLength _assetCacheOffset;
    MTLength _assetCacheInternalOffset;
    ALAssetRepresentation *_assetRepresentation;
}

#pragma mark - MTAssetReader

- (void)openAsset:(ALAssetRepresentation *)assetRepresentation
       fromOffset:(MTLength)offset
completionHandler:(void (^)(MTLength, NSError *))completionHandler {
    _assetRepresentation = assetRepresentation;
    NSError *error;
    [self p_refillCacheFromOffset:offset error:&error];
    completionHandler(_assetSize, error);
}

- (BOOL)hasBytesAvailableFromOffset:(MTLength)offset {
    if ([self p_cachedBytesCount] <= 0) {
        return NO;
    }
    return offset < _assetCacheOffset + _assetCacheSize;
}

- (BOOL)prepareForNewOffset:(MTLength)offset {
    return [self p_refillCacheFromOffset:offset error:nil];
}

- (NSInteger)read:(uint8_t *)buffer
       fromOffset:(MTLength)offset
        maxLength:(NSUInteger)maxLength
            error:(NSError **)error {
    const MTLength readResult = MIN(maxLength, [self p_cachedBytesCount]);
    memcpy(buffer, _assetCache + _assetCacheInternalOffset, (unsigned long)readResult);
    _assetCacheInternalOffset += readResult;
    const MTLength nextReadOffset = offset + readResult;
    if ([self p_cachedBytesCount] <= 0 ||
        [self p_unreadBytesCountFromOffset:nextReadOffset] > 0) {
        [self p_refillCacheFromOffset:nextReadOffset error:error];
    }
    return (NSInteger)readResult;
}

#pragma mark - Private

- (MTLength)p_unreadBytesCountFromOffset:(MTLength)offset {
    return _assetSize - offset;
}

- (MTLength)p_cachedBytesCount {
    return _assetCacheSize - _assetCacheInternalOffset;
}

- (BOOL)p_refillCacheFromOffset:(MTLength)offset error:(NSError **)error {

    const NSUInteger readResult = [_assetRepresentation getBytes:_assetCache
                                                      fromOffset:offset
                                                          length:kAssetCacheBufferSize
                                                           error:error];
    if (readResult <= 0) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Failed to read asset bytes in range %@ from asset of size %@.",
                              NSStringFromRange(NSMakeRange((NSUInteger)offset, (NSUInteger)kAssetCacheBufferSize)),
                              @(_assetSize)];
            *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                         code:-2000
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        return NO;
    }
    _assetSize = [_assetRepresentation size];
    _assetCacheSize = readResult;
    _assetCacheOffset = offset;
    _assetCacheInternalOffset = 0;
    return YES;
    
}

@end
