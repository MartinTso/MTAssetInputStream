//
//  MTAssetReader.h
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.02.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>

FOUNDATION_EXTERN NSString * const MTBlobInputStreamAssetDataSourceErrorDomain;

typedef long long MTLength;

@protocol MTAssetReader

- (void) openAsset:(id)assetRepresentation
       fromOffset:(MTLength)offset
completionHandler:(void (^)(MTLength assetSize, NSError *error))completionHandler;

- (BOOL) hasBytesAvailableFromOffset:(MTLength)offset;

- (BOOL) prepareForNewOffset:(MTLength)offset;

- (NSInteger) read:(uint8_t *)buffer
       fromOffset:(MTLength)offset
        maxLength:(NSUInteger)maxLength
            error:(NSError **)error;

@end
