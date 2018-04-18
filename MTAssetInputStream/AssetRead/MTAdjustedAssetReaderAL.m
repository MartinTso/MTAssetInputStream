//
//  MTAdjustedAssetReaderAL.m
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "MTAdjustedAssetReaderAL.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>

@interface MTAdjustedAssetReaderAL ()
@property (nonatomic) NSData *imageData;
@end

@implementation MTAdjustedAssetReaderAL {
    NSData *_imageData;
}
@dynamic imageData;

- (instancetype)init {
    if (self = [super init]) {
        _JPEGCompressionQuality = .93f;
    }
    return self;
}

#pragma mark - Properties

- (NSData *)imageData {
    @synchronized(self) {
        return _imageData;
    }
}

- (void)setImageData:(NSData *)imageData {
    @synchronized(self) {
        _imageData = imageData;
    }
}

#pragma mark - MTAssetReader

- (void) openAsset:(ALAssetRepresentation *)assetRepresentation
       fromOffset:(MTLength)offset
completionHandler:(void (^)(MTLength assetSize, NSError *error))completionHandler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSError *error;
        @autoreleasepool {
            UIImage *image = [self p_adjustedImageDataFromAssetRepresentation:assetRepresentation error:&error];
            if (image) {
                NSData *imageData = [self p_dataFromImage:image withUTI:assetRepresentation.UTI error:&error];
                if (imageData) {
                    self.imageData = [self p_dataForImageData:imageData
                                                 withMetadata:assetRepresentation.metadata
                                                        error:&error];
                }
            }
        }
        dispatch_async(self.completionDispatchQueue ?: dispatch_get_main_queue(), ^{
            completionHandler(self.imageData.length, error);
        });
    });
}

- (BOOL)hasBytesAvailableFromOffset:(MTLength)offset {
    return self.imageData.length - offset > 0;
}

- (BOOL)prepareForNewOffset:(MTLength)offset {
    return YES;
}

- (NSInteger)read:(uint8_t *)buffer
       fromOffset:(MTLength)offset
        maxLength:(NSUInteger)maxLength
            error:(NSError **)error {
    NSData *imageData = self.imageData;
    const MTLength readResult = MIN(maxLength, MAX(imageData.length - offset, 0));
    NSRange dataRange = (NSRange){
        .location = (NSUInteger)offset,
        .length = (NSUInteger)readResult
    };
    [imageData getBytes:buffer range:dataRange];
    return (NSInteger)readResult;
}

#pragma mark - Private

- (NSData *)p_dataForImageData:(NSData *)imageData
                  withMetadata:(NSDictionary *)imageMetadata
                         error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (!source) {
        if (error) *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain code:102 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to init buffer for image."
        }];
        return nil;
    }
    CFStringRef UTI = CGImageSourceGetType(source);
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, UTI, 1, NULL);
    if (!destination) {
        CFRelease(source);
        if (error) *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain code:103 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to add image data to buffer."
        }];
        return nil;
    }
    CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)imageMetadata);
    const BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CFRelease(source);
    if (!finalized) {
        if (error) *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain code:104 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to dump image data with metadata to in-memory buffer."
        }];
        return nil;
    }
    return data;
}

- (UIImage *)p_adjustedImageDataFromAssetRepresentation:(ALAssetRepresentation *)assetRepresentation
                                                  error:(NSError **)error {
    NSString *xmpString = assetRepresentation.metadata[@"AdjustmentXMP"];
    NSData *xmpData = [xmpString dataUsingEncoding:NSUTF8StringEncoding];
    CGImageRef fullResolutionImage = [assetRepresentation fullResolutionImage];
    if (!fullResolutionImage) {
        if (error) *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain code:111 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to get source image for rendering."
        }];
        return nil;
    }
    CIImage *image = [CIImage imageWithCGImage:fullResolutionImage];
    NSArray *filters = [CIFilter filterArrayFromSerializedXMP:xmpData
                                             inputImageExtent:image.extent
                                                        error:error];
    if (*error) {
        return nil;
    }
    for (CIFilter *filter in filters) {
        [filter setValue:image forKey:kCIInputImageKey];
        image = [filter outputImage];
    }
    CIContext *context = [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer : @YES }];
    CGImageRef renderedImage = [context createCGImage:image fromRect:[image extent]];
    UIImage *resultImage = [UIImage imageWithCGImage:(renderedImage ? renderedImage : fullResolutionImage)
                                               scale:[assetRepresentation scale]
                                         orientation:(UIImageOrientation)[assetRepresentation orientation]];
    if (renderedImage) {
        CGImageRelease(renderedImage);
    }
    return resultImage;
}

- (NSData *)p_dataFromImage:(UIImage *)image withUTI:(NSString *)UTI error:(NSError **)error {
    NSData *data;
    if (UTTypeConformsTo((__bridge CFStringRef)UTI, kUTTypeJPEG) ||
        UTTypeConformsTo((__bridge CFStringRef)UTI, kUTTypeJPEG2000)) {
        data = UIImageJPEGRepresentation(image, _JPEGCompressionQuality);
    } else {
        data = UIImagePNGRepresentation(image);
    }
    if (!data) {
        if (error) *error = [NSError errorWithDomain:MTBlobInputStreamAssetDataSourceErrorDomain code:121 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to generate data for image."
        }];
    }
    return data;
}

@end
