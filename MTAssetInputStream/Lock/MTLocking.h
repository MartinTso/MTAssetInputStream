//
//  MTLocking.h
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol MTLocking <NSLocking>
- (BOOL)waitWithTimeout:(dispatch_time_t)timeout;
@end

@interface MTGCDLock : NSObject <MTLocking>
@end

@interface MTDummyLock : NSObject <MTLocking>
@end
