//
//  AudioHandler.h
//  ToseeBroadcastExtention
//
//  Created by yxibng on 2021/8/30.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
NS_ASSUME_NONNULL_BEGIN


@interface TSAudioHandler: NSObject

- (void)receiveAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end


NS_ASSUME_NONNULL_END
