//
//  TSAudioHandler.m
//  ToseeBroadcastExtention
//
//  Created by yxibng on 2021/8/30.
//

#import "TSAudioHandler.h"
#import "TSAudioConverter.h"

const int bufferSamples = 16000;
size_t dataPointerSize = bufferSamples;

int16_t dataPointer[bufferSamples];
uint8_t resampleBuffer[bufferSamples];

static FILE* m_pOutFile_before = NULL;
static FILE* m_pOutFile_after = NULL;

static void writeAfterPCM(uint8_t * pcm, int length) {

    if (!m_pOutFile_after) {
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"after.pcm"];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        m_pOutFile_after = fopen([path cStringUsingEncoding:NSUTF8StringEncoding], "a+");
        NSLog(@"after path = %@", path);
    }
    fwrite(pcm, 1, length, m_pOutFile_after);
}

static void writeBeforePCM(uint8_t *pcm, int length) {
    if (!m_pOutFile_before) {
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"before.pcm"];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        m_pOutFile_before = fopen([path cStringUsingEncoding:NSUTF8StringEncoding], "a+");
        NSLog(@"before path = %@", path);
    }
    fwrite(pcm, 1, length, m_pOutFile_before);
}




static AudioStreamBasicDescription makeStreamDescription(int channels, int sampleRate) {
    
    
    bool isInterleaved = false;

    AudioStreamBasicDescription asbd;
    UInt32 bytesPerSample = sizeof(int16_t);
    asbd.mChannelsPerFrame = channels;
    asbd.mBitsPerChannel = 8 * bytesPerSample;
    asbd.mBytesPerFrame = channels * asbd.mBitsPerChannel / 8;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerPacket = asbd.mFramesPerPacket * asbd.mBytesPerFrame;
    if (isInterleaved) {
        asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    } else {
        asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsPacked;
    }
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mSampleRate = sampleRate;
    asbd.mReserved = 0;
    return asbd;
}



@interface TSAudioHandler()
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, strong) TSAudioConverter *converter;
@end



@implementation TSAudioHandler

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)receiveAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    [self.lock lock];
    [self _receiveAudioSampleBuffer:sampleBuffer];
    [self.lock unlock];
}

- (void)_receiveAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    
    OSStatus err = noErr;
    
    CMBlockBufferRef audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!audioBuffer) {
        return;
    }
    
    size_t totalBytes;
    char *samples;
    err = CMBlockBufferGetDataPointer(audioBuffer, 0, NULL, &totalBytes, &samples);
    if (!totalBytes || err != noErr) {
        return;
    }
    
    CMAudioFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *description = CMAudioFormatDescriptionGetStreamBasicDescription(format);
    
    //多少个帧（双声道包含两个采样，一个左声道一个右声道）
    size_t totalFrames = totalBytes / description->mBytesPerFrame;
    //多少个采样（双声道 = totalFrames *2）
    size_t totalSamples = totalBytes / (description->mBitsPerChannel / 8);
    UInt32 channels = description->mChannelsPerFrame;
    
    memset(dataPointer, 0, sizeof(int16_t) * bufferSamples);
    err = CMBlockBufferCopyDataBytes(audioBuffer,
                                     0,
                                     totalBytes,
                                     dataPointer);
    
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    float timestamp = CMTimeGetSeconds(pts) * 1000;
    
    BOOL isFloat = description->mFormatFlags & kAudioFormatFlagIsFloat;
    BOOL isBigEndian = description->mFormatFlags & kAudioFormatFlagIsBigEndian;
    BOOL isInterleaved = !(description->mFormatFlags & kAudioFormatFlagIsNonInterleaved);
    
    // big endian to little endian
    size_t bytesPerSample = description->mBitsPerChannel / 8;
    if (isBigEndian) {
        for (int i = 0; i < totalSamples; i++) {
            uint8_t* p = (uint8_t*)dataPointer + i * bytesPerSample;
            for (int j = 0; j < bytesPerSample / 2; j++) {
                uint8_t tmp;
                tmp = p[j];
                p[j] = p[bytesPerSample - j -1];
                p[bytesPerSample -j -1] = tmp;
            }
        }
    }
    
    // float to int
    if (isFloat) {
        float* floatData = (float*)dataPointer;
        int16_t* intData = (int16_t*)dataPointer;
        for (int i = 0; i < totalSamples; i++) {
            float tmp = floatData[i] * 32767;
            intData[i] = (tmp >= 32767) ?  32767 : tmp;
            intData[i] = (tmp < -32767) ? -32767 : tmp;
        }
        totalBytes = totalSamples * sizeof(int16_t);
    }
    
    //分离出单声道
    if (channels > 1) {
        if (isInterleaved) {
            int bytesPerFrame = (*description).mBytesPerFrame;
            for (int i = 0; i < totalFrames; i++) {
                memmove(dataPointer + i, (uint8_t *)dataPointer + i * bytesPerFrame, sizeof(int16_t));
            }
        }
    }
    
    //目前只是用了一个声道的数据
    int srcLength = (int)totalBytes / channels;
    uint8_t *srcData = (uint8_t *)dataPointer;
    writeBeforePCM(srcData, srcLength);
    
    
    if (!_converter) {
        AudioStreamBasicDescription src = makeStreamDescription(1, description->mSampleRate);
        AudioStreamBasicDescription dst = makeStreamDescription(1, 16000);
        _converter = [[TSAudioConverter alloc] initWithSrcFormat:src dstFormat:dst];
    }
    
    
    memset(resampleBuffer, 0, bufferSamples);
    int outputLength = 0;
    int outputSampleCount = 0;
    
    BOOL ret = [_converter convertMonoPCMWithSrc:srcData
                                       srcLength:srcLength
                                  srcSampleCount:srcLength/2
                                outputBufferSize:bufferSamples
                                    outputBuffer:resampleBuffer
                                    outputLength:&outputLength
                               outputSampleCount:&outputSampleCount];
    if (ret) {
        writeAfterPCM(resampleBuffer, outputLength);
    } else {
        NSLog(@"resample failed");
    }
}




@end

