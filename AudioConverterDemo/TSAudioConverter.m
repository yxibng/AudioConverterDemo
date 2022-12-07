//
//  TSAudioConverter.m
//  BroadcastExtention
//
//  Created by xiaobing yao on 2022/12/2.
//

#import "TSAudioConverter.h"
#import <AudioToolbox/AudioToolbox.h>
#import "TPCircularBuffer.h"

#define kMaxBufferSize 32767

uint8_t bufferForOutput[kMaxBufferSize];
uint8_t bufferForInput[kMaxBufferSize];



static void writePCM(uint8_t * pcm, int length) {
    static FILE* m_pOutFile = NULL;
    if (!m_pOutFile) {
        NSString *path = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.tech.tosee.mobile"].path stringByAppendingPathComponent:@"xx.pcm"];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        m_pOutFile = fopen([path cStringUsingEncoding:NSUTF8StringEncoding], "a+");
        NSLog(@"path = %@", path);
    }
    fwrite(pcm, 1, length, m_pOutFile);
}


@interface TSAudioConverter ()
{
    AudioConverterRef _converterRef;
    AudioStreamBasicDescription _srcFormat;
    AudioStreamBasicDescription _dstFormat;
    TPCircularBuffer _buffer;
}

@end


@implementation TSAudioConverter

- (void)dealloc {
    if (_converterRef) {
        AudioConverterDispose(_converterRef);
        _converterRef = nil;
    }
}

- (instancetype)initWithSrcFormat:(AudioStreamBasicDescription)srcFormat dstFormat:(AudioStreamBasicDescription)dstForamt
{
    self = [super init];
    if (self) {
        OSStatus status = AudioConverterNew(&srcFormat, &dstForamt, &_converterRef);
        if (status) {
            NSLog(@"AudioConverterNew failed, code = %d", status);
            return nil;
        }
        _srcFormat = srcFormat;
        _dstFormat = dstForamt;
        TPCircularBufferInit(&_buffer, kMaxBufferSize);
    }
    return self;
}

- (void)enqueueAudioData:(uint8_t *)audioData length:(int)length
{
    bool bRet = TPCircularBufferProduceBytes(&_buffer, audioData, length);
    if (bRet) {
        return;
    }
    TPCircularBufferConsume(&_buffer, length);
    TPCircularBufferProduceBytes(&_buffer, audioData, length);
    /*
     由于TPCircularBuffer 内部的长度是内存分页的大小，大概为4096。会一直写，写到4096的大小。
     导致 buffer 过大, 延迟变高
     手动控制 buffer 的大小不超过 kMaxBufferSize
     */
    uint32_t totalDataLength;
    TPCircularBufferTail(&_buffer, &totalDataLength);
    if (totalDataLength > kMaxBufferSize) {
        uint32_t shouldConsumeSize = totalDataLength - kMaxBufferSize;
        TPCircularBufferConsume(&_buffer, shouldConsumeSize);
    }
}

- (BOOL)dequeueLength:(int)length dstBuffer:(uint8_t *)dstBuffer
{
    uint32_t bufferLeft = 0;
    void *tmpBuffer = TPCircularBufferTail(&_buffer, &bufferLeft);
    if (bufferLeft < length) {
        return NO;
    }
    
    memcpy(dstBuffer, tmpBuffer, length);
    TPCircularBufferConsume(&_buffer, length);
    return YES;
}




- (BOOL)convertMonoPCMWithSrc:(uint8_t *)srcData
                    srcLength:(int32_t)srcLength
               srcSampleCount:(int32_t)srcSampleCount
             outputBufferSize:(int32_t)outputBufferSize
                 outputBuffer:(uint8_t *)outputBuffer
                 outputLength:(int32_t *)outputLength
            outputSampleCount:(int32_t *)outputSampleCount
{
    //计算转换后的采样个数
    int totalNumbers = floor(_dstFormat.mSampleRate / _srcFormat.mSampleRate * (Float64)srcSampleCount);
    
    [self enqueueAudioData:srcData length:srcLength];
    
    UInt32 ioOutputDataPacketSize = totalNumbers;
    UInt32 outputPacketOffset = 0;
    //循环转换
    OSStatus convertResult = noErr;
    AudioBufferList outAudioBufferList;
    while (convertResult == noErr) {
        memset(bufferForOutput, 0, kMaxBufferSize);
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = 1;
        outAudioBufferList.mBuffers[0].mDataByteSize = kMaxBufferSize;
        outAudioBufferList.mBuffers[0].mData = bufferForOutput;
        convertResult = AudioConverterFillComplexBuffer(_converterRef,
                                                        inInputDataProc,
                                                        (__bridge void * _Nullable)(self),
                                                        &ioOutputDataPacketSize,
                                                        &outAudioBufferList,
                                                        NULL);
        if (ioOutputDataPacketSize == 0) {
            break;
        }
        outputPacketOffset += ioOutputDataPacketSize;
        memcpy(outputBuffer, outAudioBufferList.mBuffers[0].mData, outAudioBufferList.mBuffers[0].mDataByteSize);
#if 0
        writePCM(outAudioBufferList.mBuffers[0].mData, outAudioBufferList.mBuffers[0].mDataByteSize);
#endif
    }
    
    *outputLength = outputPacketOffset * 2;
    *outputSampleCount = outputPacketOffset;
    
    return YES;
}


OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    TSAudioConverter *self = (__bridge TSAudioConverter *)inUserData;
    int requireSize = *ioNumberDataPackets * self->_dstFormat.mBytesPerPacket;
    if (!ioData->mBuffers[0].mData) {
        ioData->mBuffers[0].mData = bufferForInput;
        ioData->mBuffers[0].mNumberChannels = 1;
        memset(bufferForInput, 0, kMaxBufferSize);
        NSLog(@"buffer = 0");
    }
    
    NSLog(@"requireSize = %d", requireSize);
    if ([self dequeueLength:requireSize dstBuffer:ioData->mBuffers[0].mData]) {
        ioData->mBuffers[0].mDataByteSize = requireSize;
        return noErr;
    } else {
        *ioNumberDataPackets = 0;
        return -1;
    }
    
    

}

@end
