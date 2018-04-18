/*!
 @header NSInputStream+MTAsset.h
 @abstract MTAssetInputstream
 @author MartinTso
 @version 2.0.1 2017/10/20 Update
 */

#import <AssetsLibrary/AssetsLibrary.h>

@interface NSInputStream (MTAsset)

+ (NSInputStream *) mt_inputStreamWithAssetURL:(NSURL *)assetURL;
+ (NSInputStream *) mt_inputStreamWithAssetURL:(NSURL *)assetURL asynchronous:(BOOL)asynchronous;

+ (NSInputStream *) mt_inputStreamForCFNetworkWithAssetURL:(NSURL *)assetURL;
+ (NSInputStream *) mt_inputStreamForAFNetworkingWithAssetURL:(NSURL *)assetURL;

@end
