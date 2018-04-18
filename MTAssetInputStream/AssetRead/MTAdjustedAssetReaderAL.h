//
//  MTAdjustedAssetReaderAL.h
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "MTAssetReader.h"

@interface MTAdjustedAssetReaderAL : NSObject <MTAssetReader>

@property (nonatomic, assign) CGFloat JPEGCompressionQuality;

/*!
    @brief Dispatch queue for fetching ALAsset from ALAssetsLibrary.
    @remarks See MTBlobInputStreamAssetDataSource.h*/
@property (nonatomic, strong) dispatch_queue_t completionDispatchQueue;

@end
