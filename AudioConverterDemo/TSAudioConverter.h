//
//  TSAudioConverter.h
//  BroadcastExtention
//
//  Created by xiaobing yao on 2022/12/2.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSAudioConverter : NSObject

- (instancetype)initWithSrcFormat:(AudioStreamBasicDescription)srcFormat
                         dstFormat:(AudioStreamBasicDescription)dstForamt;


/*
 1. 只支持单声道转换
 2. 需要调用方申请outputBuffer
 3. 需要调用方告知buffer的大小outputBufferSize
 
 调用成功返回YES
 outputLength 保存转换后的数据大小
 outputSampleCount 保存转换后的采样个数
 */
- (BOOL)convertMonoPCMWithSrc:(uint8_t *)srcData
                    srcLength:(int32_t)srcLength
               srcSampleCount:(int32_t)srcSampleCount
             outputBufferSize:(int32_t)outputBufferSize
                  outputBuffer:(uint8_t *)outputBuffer
                  outputLength:(int32_t *)outputLength
            outputSampleCount:(int32_t *)outputSampleCount;




@end

NS_ASSUME_NONNULL_END
