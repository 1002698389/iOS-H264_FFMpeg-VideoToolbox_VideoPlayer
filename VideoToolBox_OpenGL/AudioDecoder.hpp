//
//  AudioDecoder.hpp
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 12/17/15.
//  Copyright © 2015 Cong Ku. All rights reserved.
//

#ifndef AudioDecoder_hpp
#define AudioDecoder_hpp

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

extern "C" {
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libavcodec/avcodec.h"
#include "libavformat/avio.h"
};

#include "RingBuffer.hpp"

#define AUDIO_PACKET_BUFFER_SIZE 1024*1024/2 //0.5 Mbytes
#define AUDIO_QUEUEBUFFER_SIZE 3
struct AT_FrameInfo {
    int64_t duration;
    int64_t dts;
    int64_t pts;
};

class AudioDecoder
{
public:
    bool init(AVFormatContext* formatCtx);
    void reset();
    void setStartTime(float newStartTime);
    ~AudioDecoder();
    
    bool feedPacket(AVPacket &packet);
    bool consumePacket(AudioQueueBufferRef inBuffer);
    
    float getCurrentTime();
    
    void InitAudioQueueBuffer();
    void start();
    void stop();
    void pause();
    
    void setVolume(float volume);
    void setRate(float rate);

    float convertRawTimeToSeconds(UInt64 rawTime);
    UInt64 convertSecondsToRawTime(float secs);

    int streamNum;
    
    dispatch_queue_t bufferDispatchQueue;
    
    AudioQueueRef _audioQueue;

private:
    bool audioQueueInitilized = false;
    float playbackDuration;
    float startTime; //start time for audioQueue
    
    AVCodecContext* _codecCtx;
    AVRational _context_time_base;
    
    AudioQueueBufferRef _audioQueueBuffer[AUDIO_QUEUEBUFFER_SIZE];
    
    RingBuffer<AT_FrameInfo> *_packetRingBuffer;
    uint8_t __packetBuffer[AUDIO_PACKET_BUFFER_SIZE];
};

void HandleOutputBuffer(void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer);
#endif /* AudioDecoder_hpp */
