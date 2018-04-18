//
//  ALAssetsLibrary+MTStream.h
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//


#import <AssetsLibrary/AssetsLibrary.h>

typedef void (^MTAssetLookupResultBlock)(ALAsset *asset, ALAssetsGroup *assetsGroup);

@interface ALAssetsLibrary (MTStream)

- (void) mt_assetForURL:(NSURL *)assetURL
            resultBlock:(MTAssetLookupResultBlock)resultBlock
           failureBlock:(ALAssetsLibraryAccessFailureBlock)failureBlock;

@end
