//
//  MTBlobInputStreamDataSource.h
//  MTBlobInputStreamLibrary
//
//  Created by MartinTso on 2015.07.13.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXTERN NSString * const MTBlobInputStreamDataSourceOpenCompletedKeyPath;
FOUNDATION_EXTERN NSString * const MTBlobInputStreamDataSourceHasBytesAvailableKeyPath;
FOUNDATION_EXTERN NSString * const MTBlobInputStreamDataSourceAtEndKeyPath;
FOUNDATION_EXTERN NSString * const MTBlobInputStreamDataSourceErrorKeyPath;

@protocol MTBlobInputStreamDataSource <NSObject>

//
// Self-explanatory KVO-compliant properties.
//
@property (nonatomic, readonly, getter = isOpenCompleted) BOOL openCompleted;
@property (nonatomic, readonly) BOOL hasBytesAvailable;
@property (nonatomic, readonly, getter = isAtEnd) BOOL atEnd;
@property (nonatomic, readonly) NSError *error;

//
// This selector will be called before anything else.
//
- (void)open;

//
// Data Source configuring.
//
- (id) propertyForKey:(NSString *)key;

- (BOOL)setProperty:(id)property
             forKey:(NSString *)key;

//
// Data Source data.
// The contracts of these selectors are the same as for NSInputStream.
//
- (NSInteger) read:(uint8_t *)buffer
         maxLength:(NSUInteger)maxLength;

- (BOOL) getBuffer:(uint8_t **)buffer
            length:(NSUInteger *)bufferLength;

@end
