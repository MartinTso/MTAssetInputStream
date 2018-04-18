//
//  MTBlobInputStreamAssetDataSource.m
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "MTBlobInputStreamAssetDataSource.h"
#import "MTFastAssetReader.h"
#import "MTAdjustedAssetReaderAL.h"
#import "MTAdjustedAssetReaderPH.h"
#import "MTLocking.h"
#import "ALAssetsLibrary+MTStream.h"
#include <Photos/Photos.h>

#import "MTAssetRepresentation.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>

NSString * const MTBlobInputStreamAssetDataSourceErrorDomain = @"com.github.pavelosipov.MTBlobInputStreamAssetDataSource";

static const char * const DMInputStreamSharedOpenDispatchQueueName = "com.github.pavelosipov.DMInputStreamSharedOpenDispatchQueue";

NSInteger const kDMReadFailureReturnCode = -1;

typedef NS_ENUM(int, ResetMode) {
    ResetModeReopenWhenError,
    ResetModeFailWhenError
};

@interface NSError (MTBlobInputStreamAssetDataSource)
+ (NSError *) mt_assetOpenErrorWithURL:(NSURL *)assetURL reason:(NSError *)reason;
+ (NSError *) mt_assetReadErrorWithURL:(NSURL *)assetURL reason:(NSError *)reason;
@end

@interface MTBlobInputStreamAssetDataSource ()
@property (nonatomic) NSError *error;
@property (nonatomic) NSURL *assetURL;
@property (nonatomic) ALAssetsLibrary *assetsLibrary;
@property (nonatomic) id asset;
@property (nonatomic) id assetRepresentation;
@property (nonatomic) MTLength assetSize;
@property (nonatomic) id<MTAssetReader> assetReader;
@property (nonatomic) MTLength readOffset;
@end

@implementation MTBlobInputStreamAssetDataSource

@dynamic openCompleted, hasBytesAvailable, atEnd;

#pragma mark - Lifecycle

- (id)init {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"Unexpected deadly init invokation '%@', use %@ instead.",
                                           NSStringFromSelector(_cmd),
                                           NSStringFromSelector(@selector(initWithAssetURL:))]
                                 userInfo:nil];
}

- (instancetype)initWithAssetURL:(NSURL *)assetURL {
    NSParameterAssert(assetURL);
    if (self = [super init]) {
        _openSynchronously = NO;
        _assetURL = assetURL;
        _adjustedJPEGCompressionQuality = .93f;
        _adjustedImageMaximumSize = 1024 * 1024;
    }
    return self;
}

#pragma mark - MTBlobInputStreamDataSource

+ (dispatch_queue_t)sharedOpenDispatchQueue {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create(DMInputStreamSharedOpenDispatchQueueName, NULL);
    });
    return queue;
}

- (BOOL)isOpenCompleted {
    return _assetSize > 0;
}

- (void)open {
    if (![self isOpenCompleted]) {
        [self p_open];
    }
}

- (void)setAssetSize:(MTLength)assetSize {
    const BOOL shouldEmitOpenCompletedEvent = ![self isOpenCompleted];
    if (shouldEmitOpenCompletedEvent) {
        [self willChangeValueForKey:MTBlobInputStreamDataSourceOpenCompletedKeyPath];
    }
    _assetSize = assetSize;
    if (shouldEmitOpenCompletedEvent) {
        [self didChangeValueForKey:MTBlobInputStreamDataSourceOpenCompletedKeyPath];
    }
}

- (BOOL)hasBytesAvailable {
    return [_assetReader hasBytesAvailableFromOffset:_readOffset];
}

- (BOOL)isAtEnd {
    return _assetSize <= _readOffset;
}

- (id)propertyForKey:(NSString *)key {
    if (![key isEqualToString:NSStreamFileCurrentOffsetKey]) {
        return nil;
    }
    return @(_readOffset);
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key {
    if (![key isEqualToString:NSStreamFileCurrentOffsetKey]) {
        return NO;
    }
    if (![property isKindOfClass:[NSNumber class]]) {
        return NO;
    }
    const long long requestedOffest = [property longLongValue];
    if (requestedOffest < 0) {
        return NO;
    }
    _readOffset = requestedOffest;
    if (_assetReader) {
        return [_assetReader prepareForNewOffset:_readOffset];
    }
    return YES;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)bufferLength {
    return NO;
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)maxLength {
    NSParameterAssert(buffer);
    NSParameterAssert(maxLength > 0);
    if (self.atEnd) {
        return 0;
    }
    NSError *error;
    const MTLength readResult = [_assetReader read:buffer
                                         fromOffset:_readOffset
                                          maxLength:maxLength
                                              error:&error];    
    const MTLength readOffset = _readOffset + readResult;
    NSParameterAssert(readOffset <= _assetSize);
    const BOOL atEnd = readOffset >= _assetSize;
    if (atEnd) {
        [self willChangeValueForKey:MTBlobInputStreamDataSourceAtEndKeyPath];
    }
    _readOffset = readOffset;
    if (atEnd) {
        [self didChangeValueForKey:MTBlobInputStreamDataSourceAtEndKeyPath];
    } else if (error) {
        [self p_open];
    }
    return (NSInteger)readResult;
}

#pragma mark - Private

- (void)p_open {
    id<MTLocking> lock = [self p_lockForOpening];
    [lock lock];
    dispatch_async(self.openDispatchQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
        
        NSLog(@"_assetURL.absoluteString : %@",_assetURL.absoluteString);
        
        if([_assetURL.absoluteString hasPrefix:@"assets-library:"])
        {
            self.assetsLibrary = [ALAssetsLibrary new];
            [_assetsLibrary mt_assetForURL:_assetURL resultBlock:^(ALAsset *asset, ALAssetsGroup *assetsGroup) {
                ALAssetRepresentation *assetRepresentation = [asset defaultRepresentation];
                if (assetRepresentation) {
                    self.asset = asset;
                    self.assetRepresentation = assetRepresentation;
                    self.assetReader = (assetsGroup
                                        ? [MTFastAssetReader new]
                                        : [self p_assetReaderForAssetRepresentation:assetRepresentation]);
                    [_assetReader
                     openAsset:assetRepresentation
                     fromOffset:_readOffset
                     completionHandler:^(MTLength assetSize, NSError *error) {
                         if (error != nil || assetSize <= 0 || (_assetSize != 0 && _assetSize != assetSize)) {
                             self.error = [NSError  mt_assetOpenErrorWithURL:_assetURL reason:error];
                         } else {
                             self.assetSize = assetSize;
                         }
                         [lock unlock];
                     }];
                } else {
                    self.error = [NSError  mt_assetOpenErrorWithURL:_assetURL reason:nil];
                    [lock unlock];
                }
            } failureBlock:^(NSError *error) {
                self.error = [NSError  mt_assetOpenErrorWithURL:_assetURL reason:error];
                [lock unlock];
            }];
        }else{
            PHFetchOptions *option = [[PHFetchOptions alloc] init];
            
            option.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
            
            PHFetchResult *fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[[_assetURL absoluteString]] options:option];
            
            if ([fetchResult count] == 0) {
                
                self.error = [NSError  mt_assetOpenErrorWithURL:_assetURL reason:nil];
                [lock unlock];
                
            }else{
                self.asset = [fetchResult firstObject];
                
                self.assetRepresentation = [[MTAssetRepresentation alloc] init];
                [((MTAssetRepresentation *)self.assetRepresentation) setUrl:_assetURL];
                
                self.assetReader = [self p_assetReaderForAssetRepresentation:_assetRepresentation];
                
                [_assetReader
                 openAsset:_assetRepresentation
                 fromOffset:_readOffset
                 completionHandler:^(MTLength assetSize, NSError *error) {
                     if (error != nil || assetSize <= 0 || (_assetSize != 0 && _assetSize != assetSize)) {
                         self.error = [NSError  mt_assetOpenErrorWithURL:_assetURL reason:error];
                     } else {
                         self.assetSize = assetSize;
                     }
                     [lock unlock];
                 }];
            }
        }
    }});
    [lock waitWithTimeout:DISPATCH_TIME_FOREVER];
}

- (id<MTAssetReader>)p_assetReaderForAssetRepresentation:(ALAssetRepresentation *)representation {
    if (_assetReader) {
        return _assetReader;
    }
    
    NSLog(@"asset class : %@",[_asset class]);
    
    if([_asset isKindOfClass:[PHAsset class]])
    {
        MTAdjustedAssetReaderPH *assetReader = [MTAdjustedAssetReaderPH new];
        assetReader.suspiciousSize = _adjustedImageMaximumSize;
        assetReader.completionDispatchQueue = self.openDispatchQueue;
        return assetReader;
    }
    
    return [MTFastAssetReader new];
}

- (id<MTLocking>)p_lockForOpening {
    if ([self shouldOpenSynchronously]) {
        if (!self.openDispatchQueue) {
            // If you want open stream synchronously you should
            // do that in some worker thread to avoid deadlock.
            NSParameterAssert(![[NSThread currentThread] isMainThread]);
        }
        return [MTGCDLock new];
    } else {
        return [MTDummyLock new];
    }
}

@end

@implementation NSError (MTBlobInputStreamAssetDataSource)

+ (NSError *) mt_assetOpenErrorWithURL:(NSURL *)assetURL reason:(NSError *)reason {
    NSString *description = [NSString stringWithFormat:@"Failed to open asset with URL %@", assetURL];
    if (reason) {
        return [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                   code:MTBlobInputStreamAssetDataSourceErrorCodeOpen
                               userInfo:@{ NSLocalizedDescriptionKey: description, NSUnderlyingErrorKey: reason }];
    } else {
        return [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                   code:MTBlobInputStreamAssetDataSourceErrorCodeOpen
                               userInfo:@{ NSLocalizedDescriptionKey: description }];
    }
}

+ (NSError *) mt_assetReadErrorWithURL:(NSURL *)assetURL reason:(NSError *)reason {
    NSString *description = [NSString stringWithFormat:@"Failed to read asset with URL %@", assetURL];
    if (reason) {
        return [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                   code:MTBlobInputStreamAssetDataSourceErrorCodeRead
                               userInfo:@{ NSLocalizedDescriptionKey: description, NSUnderlyingErrorKey: reason }];
    } else {
        return [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                   code:MTBlobInputStreamAssetDataSourceErrorCodeRead
                               userInfo:@{ NSLocalizedDescriptionKey: description }];
    }
}

@end
