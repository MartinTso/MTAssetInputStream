//
//  MTBlobInputStream.m
//  MTBlobInputStreamLibrary
//
//  Created by MartinTso on 2015.07.02.
//  Copyright (c) 2015 MartinTso. All rights reserved.
//

#import "MTBlobInputStream.h"
#import "MTBlobInputStreamDataSource.h"
#import <objc/runtime.h>

NSString * const MTBlobInputStreamErrorDomain = @"com.dmsys.martin.MTBlobInputStreamErrorDomain";

NSString * const MTBlobInputStreamDataSourceOpenCompletedKeyPath = @"openCompleted";
NSString * const MTBlobInputStreamDataSourceHasBytesAvailableKeyPath = @"hasBytesAvailable";
NSString * const MTBlobInputStreamDataSourceAtEndKeyPath = @"atEnd";
NSString * const MTBlobInputStreamDataSourceErrorKeyPath = @"error";

static NSInteger const kOperationFailedReturnCode = -1;
static char const MTBlobInputStreamObservingContext;

#pragma mark - Core Foundation callbacks

static const void *DMRetainCallBack(CFAllocatorRef allocator, const void *value) { return CFRetain(value); }
static void DMReleaseCallBack(CFAllocatorRef allocator, const void *value)       { CFRelease(value); }

static void DMRunLoopPerformCallBack(void *info);

#pragma mark - MTBlobInputStream ()

@interface MTBlobInputStream () <NSStreamDelegate> {
    __weak id<NSStreamDelegate> _delegate;
    CFRunLoopSourceRef _runLoopSource;
    NSObject<MTBlobInputStreamDataSource> *_dataSource;
    NSStreamEvent _pendingEvents;
    NSStreamStatus _status;
    NSError *_error;
    NSMutableDictionary *_properties;
    CFReadStreamClientCallBack _clientCallBack;
    CFStreamClientContext _clientContext;
    CFOptionFlags _clientFlags;
    CFMutableSetRef _runLoopsSet;
    CFMutableDictionaryRef _runLoopsModes;
}

@end

#pragma mark - MTBlobInputStream

@implementation MTBlobInputStream

- (id)init {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"Unexpected deadly init invokation '%@', use %@ instead.",
                                           NSStringFromSelector(_cmd),
                                           NSStringFromSelector(@selector(initWithDataSource:))]
                                 userInfo:nil];
}

- (id)initWithDataSource:(NSObject<MTBlobInputStreamDataSource> *)dataSource {
    NSParameterAssert(dataSource);
    if (self = [super init]) {
        _shouldNotifyCoreFoundationAboutStatusChange = NO;
        [self setDataSource:dataSource];
        CFRunLoopSourceContext runLoopSourceContext = {
            0, (__bridge void *)(self), NULL, NULL, NULL, NULL, NULL, NULL, NULL, DMRunLoopPerformCallBack
        };
        _runLoopSource = CFRunLoopSourceCreate(NULL, 0, &runLoopSourceContext);
        _status = NSStreamStatusNotOpen;
        _delegate = self;
        _clientCallBack = NULL;
        _clientContext = (CFStreamClientContext) { 0 };
        CFSetCallBacks runLoopsSetCallBacks = {
            0, NULL, NULL, NULL, CFEqual, CFHash // CFRunLoop retains CFStream, so we will not.
        };
        _runLoopsSet = CFSetCreateMutable(NULL, 0, &runLoopsSetCallBacks);
        CFDictionaryKeyCallBacks runLoopsModesKeyCallBacks = {
            0, NULL, NULL, NULL, CFEqual, CFHash
        };
        CFDictionaryValueCallBacks runLoopsModesValueCallBacks = {
            0, DMRetainCallBack, DMReleaseCallBack, NULL, CFEqual
        };
        _runLoopsModes = CFDictionaryCreateMutable(NULL, 0, &runLoopsModesKeyCallBacks, &runLoopsModesValueCallBacks);
    }
    return self;
}

#pragma mark - NSInputStream

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)maxLength {
    if (![self isOpen]) {

        [self open];
        
        if (![self isOpen])
        {
            NSLog(@"%@: rejected attempt to read stream with status %ld.", self, (long)_status);
            return kOperationFailedReturnCode;
        }
    }
    if (_status == NSStreamStatusAtEnd) {
        return 0;
    }
    const NSInteger readResult = [_dataSource read:buffer maxLength:maxLength];
    if (readResult < 0) {
        return kOperationFailedReturnCode;
    }
    if ([_dataSource hasBytesAvailable]) {
        [self enqueueEvent:NSStreamEventHasBytesAvailable];
    }
    return readResult;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)bufferLength {
    return [_dataSource getBuffer:buffer length:bufferLength];
}

- (BOOL)hasBytesAvailable {
    switch (_status) {
        case NSStreamStatusNotOpen: {
            NSLog(@"%@: you should open stream before fetching for available bytes.", self);
            return NO;
        }
        case NSStreamStatusError: {
            NSLog(@"%@: stream is in error state.", self);
            return NO;
        }
        default: {
            return [_dataSource hasBytesAvailable];
        }
    }
}

#pragma mark - NSStream

- (void)open {
    if (_status != NSStreamStatusNotOpen) {
        NSLog(@"%@: reject attempt to reopen stream. %ld", self,_status);
        return;
    }
    [self setStatus:NSStreamStatusOpening];
    [_dataSource open];
}

- (void)close {
    if (![self isOpen]) {
        return;
    }
    [self unscheduleFromAllRunLoops];
    [self setStatus:NSStreamStatusClosed];
}

- (id<NSStreamDelegate>)delegate {
    return _delegate;
}

- (void)setDelegate:(id<NSStreamDelegate>)delegate {
    _delegate = delegate;
    if (!_delegate) {
        _delegate = self;
    }
}

- (id)propertyForKey:(NSString *)key {
    return [_dataSource propertyForKey:key];
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key {
    return [_dataSource setProperty:property forKey:key];
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [self scheduleInCFRunLoop:[aRunLoop getCFRunLoop] forMode:(CFStringRef) mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [self unscheduleFromCFRunLoop:[aRunLoop getCFRunLoop] forMode:(CFStringRef) mode];
}

- (NSStreamStatus)streamStatus {
    if (_status == NSStreamStatusError && !_shouldNotifyCoreFoundationAboutStatusChange) {
        return NSStreamStatusOpen;
    }
    return _status;
}

- (NSError *)streamError {
    NSError *dataSourceError = [_dataSource error];
    if (dataSourceError) {
        return [NSError errorWithDomain:MTBlobInputStreamErrorDomain
                                   code:MTBlobInputStreamErrorCodeDataSourceFailure
                               userInfo:@{ NSUnderlyingErrorKey : dataSourceError }];
    } else {
        return nil;
    }
}

#pragma mark - NSObject

+ (BOOL)resolveInstanceMethod:(SEL)selector {
    NSString *name = NSStringFromSelector(selector);
    if ([name hasPrefix:@"_"]) {
        name = [name substringFromIndex:1];
        SEL aSelector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(self, aSelector);
        if (method) {
            class_addMethod(self,
                            selector,
                            method_getImplementation(method),
                            method_getTypeEncoding(method));
            return YES;
        }
    }
    return [super resolveInstanceMethod:selector];
}

- (void)dealloc {
    if ([self isOpen]) {
        [self close];
    }
    if (_clientContext.release) {
        _clientContext.release(_clientContext.info);
    }
    CFRelease(_runLoopSource);
    CFRelease(_runLoopsSet);
    CFRelease(_runLoopsModes);
    [_dataSource removeObserver:self forKeyPath:MTBlobInputStreamDataSourceOpenCompletedKeyPath];
    [_dataSource removeObserver:self forKeyPath:MTBlobInputStreamDataSourceHasBytesAvailableKeyPath];
    [_dataSource removeObserver:self forKeyPath:MTBlobInputStreamDataSourceAtEndKeyPath];
    [_dataSource removeObserver:self forKeyPath:MTBlobInputStreamDataSourceErrorKeyPath];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &MTBlobInputStreamObservingContext) {
        id newValue = [change objectForKey:NSKeyValueChangeNewKey];
        if ([keyPath isEqualToString:MTBlobInputStreamDataSourceOpenCompletedKeyPath] && [newValue boolValue]) {
            [self setStatus:NSStreamStatusOpen];
            [self enqueueEvent:NSStreamEventOpenCompleted];
        } else if ([keyPath isEqualToString:MTBlobInputStreamDataSourceHasBytesAvailableKeyPath] && [newValue boolValue]) {
            [self enqueueEvent:NSStreamEventHasBytesAvailable];
        } else if ([keyPath isEqualToString:MTBlobInputStreamDataSourceAtEndKeyPath] && [newValue boolValue]) {
            [self setStatus:NSStreamStatusAtEnd];
            [self enqueueEvent:NSStreamEventEndEncountered];
        } else if ([keyPath isEqualToString:MTBlobInputStreamDataSourceErrorKeyPath] && newValue != nil) {
            [self setError:newValue];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - MTBlobInputStream Private

- (void)setDataSource:(NSObject<MTBlobInputStreamDataSource> *)dataSource {
    _dataSource = dataSource;
    [_dataSource addObserver:self
                  forKeyPath:MTBlobInputStreamDataSourceOpenCompletedKeyPath
                     options:NSKeyValueObservingOptionNew
                     context:(void *)&MTBlobInputStreamObservingContext];
    [_dataSource addObserver:self
                  forKeyPath:MTBlobInputStreamDataSourceHasBytesAvailableKeyPath
                     options:NSKeyValueObservingOptionNew
                     context:(void *)&MTBlobInputStreamObservingContext];
    [_dataSource addObserver:self
                  forKeyPath:MTBlobInputStreamDataSourceAtEndKeyPath
                     options:NSKeyValueObservingOptionNew
                     context:(void *)&MTBlobInputStreamObservingContext];
    [_dataSource addObserver:self
                  forKeyPath:MTBlobInputStreamDataSourceErrorKeyPath
                     options:NSKeyValueObservingOptionNew
                     context:(void *)&MTBlobInputStreamObservingContext];
}

- (BOOL)isOpen {
    return (_status != NSStreamStatusNotOpen &&
            _status != NSStreamStatusOpening &&
            _status != NSStreamStatusClosed &&
            _status != NSStreamStatusError);
    
}

- (void)setStatus:(NSStreamStatus)aStatus {
    _status = aStatus;
}

- (void)setError:(NSError *)theError {
    [self setStatus:NSStreamStatusError];
    [self enqueueEvent:NSStreamEventErrorOccurred];
    _error = theError;
}

- (void)enqueueEvent:(NSStreamEvent)event {
    _pendingEvents |= event;
    CFRunLoopSourceSignal(_runLoopSource);
    [self enumerateRunLoopsUsingBlock:^(CFRunLoopRef runLoop) {
        CFRunLoopWakeUp(runLoop);
    }];
}

- (NSStreamEvent)dequeueEvent {
    if (_pendingEvents == NSStreamEventNone) {
        return NSStreamEventNone;
    }
    NSStreamEvent event = 1UL << __builtin_ctz(_pendingEvents);
    _pendingEvents ^= event;
    return event;
}

- (void)streamEventTrigger {
    if (_status == NSStreamStatusClosed) {
        return;
    }
    NSStreamEvent event = [self dequeueEvent];
    while (event != NSStreamEventNone) {
        if ([_delegate respondsToSelector:@selector(stream:handleEvent:)]) {
            [_delegate stream:self handleEvent:event];
        }
        if (_clientCallBack && (event & _clientFlags) && _shouldNotifyCoreFoundationAboutStatusChange) {
            _clientCallBack((__bridge CFReadStreamRef)self, (CFStreamEventType)event, _clientContext.info);
        }
        event = [self dequeueEvent];
    }
}

- (void)enumerateRunLoopsUsingBlock:(void (^)(CFRunLoopRef runLoop))block {
    CFIndex runLoopsCount = CFSetGetCount(_runLoopsSet);
    if (runLoopsCount > 0) {
        CFTypeRef runLoops[runLoopsCount];
        CFSetGetValues(_runLoopsSet, runLoops);
        for (CFIndex i = 0; i < runLoopsCount; ++i) {
            block((CFRunLoopRef)runLoops[i]);
        }
    }
}

- (void)addMode:(CFStringRef)mode forRunLoop:(CFRunLoopRef)runLoop {
    CFMutableSetRef modes = NULL;
    if (!CFDictionaryContainsKey(_runLoopsModes, runLoop)) {
        CFSetCallBacks modesSetCallBacks = {
            0, DMRetainCallBack, DMReleaseCallBack, NULL, CFEqual, CFHash
        };
        modes = CFSetCreateMutable(NULL, 0, &modesSetCallBacks);
        CFDictionaryAddValue(_runLoopsModes, runLoop, modes);
    } else {
        modes = (CFMutableSetRef)CFDictionaryGetValue(_runLoopsModes, runLoop);
    }
    CFStringRef modeCopy = CFStringCreateCopy(NULL, mode);
    CFSetAddValue(modes, modeCopy);
    CFRelease(modeCopy);
}

- (void)removeMode:(CFStringRef)mode forRunLoop:(CFRunLoopRef)runLoop {
    if (!CFDictionaryContainsKey(_runLoopsModes, runLoop)) {
        return;
    }
    CFMutableSetRef modes = (CFMutableSetRef)CFDictionaryGetValue(_runLoopsModes, runLoop);
    CFSetRemoveValue(modes, mode);
}

- (void)scheduleInCFRunLoop:(CFRunLoopRef)runLoop forMode:(CFStringRef)mode {
    CFSetAddValue(_runLoopsSet, runLoop);
    [self addMode:mode forRunLoop:runLoop];
    CFRunLoopAddSource(runLoop, _runLoopSource, mode);
}

- (void)unscheduleFromCFRunLoop:(CFRunLoopRef)runLoop forMode:(CFStringRef)mode {
    CFRunLoopRemoveSource(runLoop, _runLoopSource, mode);
    [self removeMode:mode forRunLoop:runLoop];
    CFSetRemoveValue(_runLoopsSet, runLoop);
}

- (void)unscheduleFromAllRunLoops {
    [self enumerateRunLoopsUsingBlock:^(CFRunLoopRef runLoop) {
        CFMutableSetRef runLoopModesSet = (CFMutableSetRef)CFDictionaryGetValue(_runLoopsModes, runLoop);
        CFIndex runLoopModesCount = CFSetGetCount(runLoopModesSet);
        if (runLoopModesCount > 0) {
            CFTypeRef runLoopModes[runLoopModesCount];
            CFSetGetValues(runLoopModesSet, runLoopModes);
            for (CFIndex j = 0; j < runLoopModesCount; ++j) {
                [self unscheduleFromCFRunLoop:runLoop forMode:(CFStringRef)runLoopModes[j]];
            }
        }
    }];
}

- (BOOL)setCFClientFlags:(CFOptionFlags)flags
                callback:(CFReadStreamClientCallBack)callBack
                 context:(CFStreamClientContext *)context {
    if (context && context->version != 0) {
        return NO;
    }
    if (_clientContext.release) {
        _clientContext.release(_clientContext.info);
    }
    _clientContext = (CFStreamClientContext) { 0 };
    if (context) {
        _clientContext = *context;
    }
    if (_clientContext.retain) {
        _clientContext.retain(_clientContext.info);
    }
    _clientFlags = flags;
    _clientCallBack = callBack;
    return YES;
}

@end

#pragma mark - Core Foundation callbacks implementations

void DMRunLoopPerformCallBack(void *info) {
    MTBlobInputStream *stream = (__bridge MTBlobInputStream *)info;
    [stream streamEventTrigger];
}
