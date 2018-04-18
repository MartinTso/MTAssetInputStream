//
//  MTBlobInputStream.h
//  MTBlobInputStreamLibrary
//
//  Created by MartinTso on 2015.07.02.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXTERN NSString * const MTBlobInputStreamErrorDomain;

typedef NS_ENUM(NSUInteger, MTBlobInputStreamErrorCode) {
    MTBlobInputStreamErrorCodeDataSourceFailure = 0
};

@protocol MTBlobInputStreamDataSource;

@interface MTBlobInputStream : NSInputStream

@property (nonatomic, assign) BOOL shouldNotifyCoreFoundationAboutStatusChange;

// Designated initializer.
- (id)initWithDataSource:(NSObject<MTBlobInputStreamDataSource> *)dataSource;

@end
