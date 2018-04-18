//
//  MTAdjustedAssetReaderPH.m
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "MTAdjustedAssetReaderPH.h"
#import <Photos/Photos.h>

#import "MTAssetRepresentation.h"

@interface MTAdjustedAssetReaderPH ()
@property (nonatomic) NSData *imageData;
@property (nonatomic) NSFileHandle *fileHandle;
@property (nonatomic ,assign) long long length;
@end

@implementation MTAdjustedAssetReaderPH

- (instancetype)init {
    if (self = [super init]) {
        _suspiciousSize = LONG_LONG_MAX;
    }
    return self;
}

#pragma mark - MTAssetReader

- (void)openAsset:(MTAssetRepresentation *)assetRepresentation
       fromOffset:(MTLength)offset
completionHandler:(void (^)(MTLength assetSize, NSError *error))completionHandler {
    NSError *error;
    PHAsset *asset = [self p_fetchAssetForWithURL:assetRepresentation.url error:&error];
    if (!asset) {
        completionHandler(0, error);
        return;
    }
    // 视频
    void (^openVideoCompletionBlock)(NSFileHandle *, long long, NSError *) = ^void(NSFileHandle *fileHandle, long long length, NSError *error) {
        self.fileHandle = fileHandle;
        self.length = length;
        dispatch_async(self.completionDispatchQueue ?: dispatch_get_main_queue(), ^{
            completionHandler(length, error);
        });
    };
    // 照片
    void (^openImageCompletionBlock)(NSData *, NSError *) = ^void(NSData *imageData, NSError *error) {
        self.imageData = imageData;
        dispatch_async(self.completionDispatchQueue ?: dispatch_get_main_queue(), ^{
            completionHandler([imageData length], error);
        });
    };
    [self p_fetchAssetDataForAsset:asset videoBlock:^(NSFileHandle *fileHandle, long long length, NSError *error) {
        if (length <= _suspiciousSize) {
            [self p_fetchAssetDataForAsset:asset videoBlock:openVideoCompletionBlock imageBlock:nil];
        } else {
            openVideoCompletionBlock(fileHandle, length, error);
        }
    } imageBlock:^(NSData *imageData, NSError *error) {
        if ([imageData length] <= _suspiciousSize) {
            [self p_fetchAssetDataForAsset:asset videoBlock:nil imageBlock:openImageCompletionBlock];
        } else {
            openImageCompletionBlock(imageData, error);
        }
    }];
}

- (BOOL)hasBytesAvailableFromOffset:(MTLength)offset {
    if (_fileHandle) {
        return _length - offset > 0;
    }else {
        return [_imageData length] - offset > 0;
    }
}

- (BOOL)prepareForNewOffset:(MTLength)offset {
    return YES;
}

- (NSInteger)read:(uint8_t *)buffer
       fromOffset:(MTLength)offset
        maxLength:(NSUInteger)maxLength
            error:(NSError **)error {
    long long length = _fileHandle ? _length : _imageData.length;
    const MTLength readResult = MIN(maxLength, MAX(length - offset, 0));
    if (_fileHandle) {
        [_fileHandle seekToFileOffset:offset];
        const void *bytes = [[_fileHandle readDataOfLength:(unsigned long)readResult] bytes];
        memcpy(buffer, bytes, (unsigned long)readResult);
    }else {
        NSRange dataRange = (NSRange){
            .location = (NSUInteger)offset,
            .length = (NSUInteger)readResult
        };
        [_imageData getBytes:buffer range:dataRange];
    }
    return (NSInteger)readResult;
}

#pragma mark - Private

- (PHAsset *)p_fetchAssetForWithURL:(NSURL *)assetURL error:(NSError **)error {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
    
    PHFetchResult *assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[[assetURL absoluteString]] options:options];
    if ([assets count] == 0) {
        if (error) *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                                code:201
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Image not found." }];
        return nil;
    }
    return [assets firstObject];
}

- (void)p_fetchAssetDataForAsset:(PHAsset *)asset
                      videoBlock:(void (^)(NSFileHandle *fileHandle, long long length, NSError *error))videoBlock imageBlock:(void (^)(NSData *imageData, NSError *error))imageBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ @autoreleasepool {
        if(asset.mediaType == PHAssetMediaTypeVideo)
        {
            
            PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
            options.version = PHVideoRequestOptionsVersionOriginal;
            
            [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *avasset, AVAudioMix *audioMix, NSDictionary *info) {
                
                if ([avasset isKindOfClass:[AVURLAsset class]]) {
                    
                    AVURLAsset* urlAsset = (AVURLAsset*)avasset;
                    
                    NSError *error;
                    
//                    NSData *videoData=[[NSData alloc] initWithContentsOfURL:urlAsset.URL options:NSDataReadingMappedIfSafe error:&error];
                    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:urlAsset.URL error:&error];
                    NSNumber *size;
                    [urlAsset.URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
                    long long length = [size longLongValue];
                    videoBlock(fileHandle, length, error);
                    
                }
            }];
        }else{
            PHImageManager *imageManager = [PHImageManager defaultManager];
            PHImageRequestOptions *options = [PHImageRequestOptions new];
            options.version = PHImageRequestOptionsVersionCurrent;
            options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
            options.resizeMode = PHImageRequestOptionsResizeModeNone;
            options.synchronous = YES;
            options.networkAccessAllowed = NO;
            [imageManager
             requestImageDataForAsset:asset
             options:options
             resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
                 if (info[PHImageErrorKey] != nil) {
                     NSError *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                                          code:211
                                                      userInfo:@{ NSLocalizedDescriptionKey: @"Failed to fetch data for image.",
                                                                  NSUnderlyingErrorKey: info[PHImageErrorKey]}];
                     imageBlock(nil, error);
                 } else if ([info[PHImageCancelledKey] boolValue]) {
                     NSError *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                                          code:212
                                                      userInfo:@{ NSLocalizedDescriptionKey: @"Fetching data for image was canceled."}];
                     imageBlock(nil, error);
                 } else if ([info[PHImageResultIsInCloudKey] boolValue]) {
                     NSError *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain
                                                          code:213
                                                      userInfo:@{ NSLocalizedDescriptionKey: @"Image is located in the cloud."}];
                     imageBlock(nil, error);
                 } else {
                     imageBlock(imageData, nil);
                 }
             }];
        }
        
    }});
}

@end
