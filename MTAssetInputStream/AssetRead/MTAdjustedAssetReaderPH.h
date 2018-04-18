//
//  MTAdjustedAssetReaderIOS8.h
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "MTAssetReader.h"

@interface MTAdjustedAssetReaderPH : NSObject <MTAssetReader>

/// When you try to get adjusted photo just after taking it in Camera app,
/// Photos framework will provide data of 'SubstandardFullSizeRender.jpg'.
/// Asset reader will force Photos framework to generate 'FullSizeRender.jpg'
/// making 2nd attempt to open asset. I think a "suspicious" image size is
/// more adequate parameter to rely on, than the name of the file which you
/// can take from the info dictionary with 'PHImageFileURLKey' key.
@property (nonatomic, assign) long long suspiciousSize;

/*!
    @brief Dispatch queue for fetching ALAsset from ALAssetsLibrary.
    @remarks See MTBlobInputStreamAssetDataSource.h*/
@property (nonatomic, strong) dispatch_queue_t completionDispatchQueue;

@end
