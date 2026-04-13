//
//  TSAudioConverter.m
//  BroadcastExtention
//
//  Created by xiaobing yao on 2022/12/2.
//

#import "TSAudioConverter.h"
#import <AudioToolbox/AudioToolbox.h>
#import "TPCircularBuffer.h"

#define kMaxBufferSize 96000

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
    TPCircularBufferCleanup(&_buffer);
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
    if (!bRet) {
        NSLog(@"TPCircularBufferProduceBytes failed, length = %d", length);
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
    if (!_converterRef || !srcData || srcLength <= 0 || !outputBuffer || outputBufferSize <= 0 || !outputLength || !outputSampleCount) {
        return NO;
    }

    if (_dstFormat.mBytesPerPacket == 0 || _dstFormat.mBytesPerFrame == 0) {
        return NO;
    }

    //计算转换后的采样个数
    int totalNumbers = floor(_dstFormat.mSampleRate / _srcFormat.mSampleRate * (Float64)srcSampleCount);
    if (totalNumbers <= 0) {
        *outputLength = 0;
        *outputSampleCount = 0;
        return YES;
    }
    
    [self enqueueAudioData:srcData length:srcLength];
    
    UInt32 outputPacketOffset = 0;
    UInt32 outputByteOffset = 0;
    //循环转换
    AudioBufferList outAudioBufferList;
    while (outputPacketOffset < (UInt32)totalNumbers && outputByteOffset < (UInt32)outputBufferSize) {
        UInt32 remainingPackets = (UInt32)totalNumbers - outputPacketOffset;
        UInt32 remainingBytes = (UInt32)outputBufferSize - outputByteOffset;
        UInt32 maxPacketsByBuffer = remainingBytes / _dstFormat.mBytesPerPacket;
        UInt32 ioOutputDataPacketSize = MIN(remainingPackets, maxPacketsByBuffer);
        if (ioOutputDataPacketSize == 0) {
            break;
        }

        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = 1;
        outAudioBufferList.mBuffers[0].mDataByteSize = remainingBytes;
        outAudioBufferList.mBuffers[0].mData = outputBuffer + outputByteOffset;

        OSStatus convertResult = AudioConverterFillComplexBuffer(_converterRef,
                                                                 inInputDataProc,
                                                                 (__bridge void * _Nullable)(self),
                                                                 &ioOutputDataPacketSize,
                                                                 &outAudioBufferList,
                                                                 NULL);

        if (convertResult != noErr && ioOutputDataPacketSize == 0) {
            break;
        }
        if (convertResult != noErr) {
            NSLog(@"AudioConverterFillComplexBuffer failed, code = %d", (int)convertResult);
            return NO;
        }
        if (ioOutputDataPacketSize == 0) {
            break;
        }

        UInt32 producedBytes = ioOutputDataPacketSize * _dstFormat.mBytesPerPacket;
        if (producedBytes > outAudioBufferList.mBuffers[0].mDataByteSize) {
            producedBytes = outAudioBufferList.mBuffers[0].mDataByteSize;
        }

        outputPacketOffset += ioOutputDataPacketSize;
        outputByteOffset += producedBytes;
#if 0
        writePCM(outAudioBufferList.mBuffers[0].mData, outAudioBufferList.mBuffers[0].mDataByteSize);
#endif
    }
    
    *outputLength = (int32_t)outputByteOffset;
    *outputSampleCount = (int32_t)(outputByteOffset / _dstFormat.mBytesPerFrame);
    
    return YES;
}


OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    TSAudioConverter *self = (__bridge TSAudioConverter *)inUserData;
    int requireSize = *ioNumberDataPackets * self->_srcFormat.mBytesPerPacket;
    ioData->mNumberBuffers = 1;
    if (!ioData->mBuffers[0].mData) {
        ioData->mBuffers[0].mData = bufferForInput;
        ioData->mBuffers[0].mNumberChannels = 1;
        memset(bufferForInput, 0, kMaxBufferSize);
    }

    if (requireSize > kMaxBufferSize) {
        *ioNumberDataPackets = 0;
        ioData->mBuffers[0].mDataByteSize = 0;
        return noErr;
    }

    if ([self dequeueLength:requireSize dstBuffer:ioData->mBuffers[0].mData]) {
        ioData->mBuffers[0].mDataByteSize = requireSize;
        return noErr;
    } else {
        *ioNumberDataPackets = 0;
        ioData->mBuffers[0].mDataByteSize = 0;
        return noErr;
    }
    
    

}

@end
