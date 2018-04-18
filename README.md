## Introduce
· 必须在Thread中Open.

· 分synchronous及asynchronous两种模式.

· stream的方式读取ALAsset/PHAsset中的Photo/Video，避免直接读取导致Memory飙升。

· 复写read:maxLength:实现seek以达到断点续传所需数据读取。


## How Use

### import
```objective-c
#import <MTAssetInputStream/MTAssetInputStream.h>
```

### create
```objective-c
NSURL *assetUrl = [NSURL URLWithString:@"your asset identifier"];
NSInputStream *assetStream = [NSInputStream mt_inputStreamWithAssetURL:assetUrl asynchronous:NO];
[assetStream open];

//here you can operate assetStream

[assetStream close];
```

### active read
```objective-c
+ (int) mtReadFileStreamBuffer:(id)streamSeq
                        buffer:(uint8_t *)buffer
                     maxLength:(NSUInteger)len {
    @autoreleasepool {
        NSInputStream *assetStream = (NSInputStream *)transportStreams[streamSeq];
        if(assetStream == nil) {
            return 0;
        }
        int gotByteCount = (int)[assetStream read:buffer maxLength:len];
        return gotByteCount;
    }
}
```

### Note
· must open stream in child thread.
· if local file, please use system api
```objective-c
- (nullable instancetype)initWithFileAtPath:(NSString *)path;

+ (nullable instancetype)inputStreamWithData:(NSData *)data;
+ (nullable instancetype)inputStreamWithFileAtPath:(NSString *)path;
+ (nullable instancetype)inputStreamWithURL:(NSURL *)url API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));
```
