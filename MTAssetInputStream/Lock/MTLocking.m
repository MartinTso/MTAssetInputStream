//
//  MTLocking.m
//  MTAssetInputstream
//
//  Created by MartinTso on 2015.07.01.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "MTLocking.h"

@implementation MTGCDLock {
    dispatch_semaphore_t semaphore_;
}

- (void)lock {
    semaphore_ = dispatch_semaphore_create(0);
}

- (void)unlock {
    dispatch_semaphore_signal(semaphore_);
}

- (BOOL)waitWithTimeout:(dispatch_time_t)timeout {
    return dispatch_semaphore_wait(semaphore_, timeout) == 0;
}

@end

@implementation MTDummyLock
- (void)lock {}
- (void)unlock {}
- (BOOL)waitWithTimeout:(dispatch_time_t)timeout { return YES; }
@end
