//
//  NSInputStream+DM.m
//  MTBlobInputStreamLibrary
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "NSInputStream+MTAsset.h"

#import "MTBlobInputStream.h"
#import "MTBlobInputStreamAssetDataSource.h"

@implementation NSInputStream (MTAsset)

+ (NSInputStream *) mt_inputStreamWithAssetURL:(NSURL *)assetURL {
    return [NSInputStream  mt_inputStreamWithAssetURL:assetURL asynchronous:YES];
}

+ (NSInputStream *) mt_inputStreamWithAssetURL:(NSURL *)assetURL asynchronous:(BOOL)asynchronous {
    MTBlobInputStreamAssetDataSource *dataSource = [[MTBlobInputStreamAssetDataSource alloc] initWithAssetURL:assetURL];
    dataSource.openSynchronously = !asynchronous;
    MTBlobInputStream *stream = [[MTBlobInputStream alloc] initWithDataSource:dataSource];
    stream.shouldNotifyCoreFoundationAboutStatusChange = YES;
    return stream;
}

+ (NSInputStream *) mt_inputStreamForCFNetworkWithAssetURL:(NSURL *)assetURL {
    MTBlobInputStreamAssetDataSource *dataSource = [[MTBlobInputStreamAssetDataSource alloc] initWithAssetURL:assetURL];
    dataSource.openSynchronously = YES;
    MTBlobInputStream *stream = [[MTBlobInputStream alloc] initWithDataSource:dataSource];
    stream.shouldNotifyCoreFoundationAboutStatusChange = NO;
    return stream;
}

+ (NSInputStream *) mt_inputStreamForAFNetworkingWithAssetURL:(NSURL *)assetURL {
    MTBlobInputStreamAssetDataSource *dataSource = [[MTBlobInputStreamAssetDataSource alloc] initWithAssetURL:assetURL];
    dataSource.openSynchronously = YES;
    dataSource.openDispatchQueue = MTBlobInputStreamAssetDataSource.sharedOpenDispatchQueue;
    MTBlobInputStream *stream = [[MTBlobInputStream alloc] initWithDataSource:dataSource];
    stream.shouldNotifyCoreFoundationAboutStatusChange = NO;
    return stream;
}

@end
