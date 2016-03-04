//
//  AudioDecoder.cpp
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 12/17/15.
//  Copyright © 2015 Cong Ku. All rights reserved.
//

#include "AudioDecoder.hpp"
#define AUDIO_FORMAT_AAC 0x15002


bool AudioDecoder::init(AVFormatContext* formatCtx)
{
    //create buffers
    _packetRingBuffer = new RingBuffer<AT_FrameInfo>(__packetBuffer, AUDIO_PACKET_BUFFER_SIZE);
    
    streamNum = av_find_best_stream(formatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    if (streamNum < 0) {
        return false;
    }
    
    //create decode context
    _codecCtx = formatCtx->streams[streamNum]->codec;
    AVCodec* codec = avcodec_find_decoder(_codecCtx->codec_id);
    if (avcodec_open2(_codecCtx, codec, nil) < 0)
        return false;
    

    _context_time_base = formatCtx->streams[streamNum]->time_base;
    
    AudioStreamBasicDescription _audioFormat;

    //get audio format description
    if (_codecCtx->codec_id == AV_CODEC_ID_AAC)
    {
        _audioFormat.mSampleRate = _codecCtx->sample_rate;
        _audioFormat.mFormatFlags = (_codecCtx->profile == FF_PROFILE_AAC_LOW) ? kMPEG4Object_AAC_LC : kMPEG4Object_AAC_Main;
        _audioFormat.mFormatID = _codecCtx->profile ==FF_PROFILE_AAC_HE ? kAudioFormatMPEG4AAC_HE : kAudioFormatMPEG4AAC;
        _audioFormat.mBytesPerPacket = 0;
        _audioFormat.mBytesPerFrame = 0;
        _audioFormat.mFramesPerPacket = _codecCtx->frame_size;

        _audioFormat.mChannelsPerFrame = _codecCtx->channels;
        _audioFormat.mBitsPerChannel = 0;
        
        NSLog(@"Audio sample rate: %d", _codecCtx->sample_rate);
        NSLog(@"Audio format flag: %u", (unsigned int)_audioFormat.mFormatFlags);
        NSLog(@"Audio format ID: %u", (unsigned int)_audioFormat.mFormatID);
        NSLog(@"Audio bytes per packet: %d", (unsigned int)_audioFormat.mBytesPerPacket);
        NSLog(@"Audio bytes per frame: %d", (unsigned int)_audioFormat.mBytesPerFrame);
        NSLog(@"Audio frames per packet: %d", (unsigned int)_audioFormat.mFramesPerPacket);
        NSLog(@"Audio channels per frame: %d", (unsigned int)_audioFormat.mChannelsPerFrame);
        NSLog(@"Audio bits per channel: %d", (unsigned int)_audioFormat.mBitsPerChannel);
    }
    else
    {
        return false;
    }
    
    if (AudioQueueNewOutput(&_audioFormat, HandleOutputBuffer, this, NULL, NULL, 0, &_audioQueue) != noErr)
        NSLog(@"Error: Could not create audioQueue");
    for (int i = 0; i < AUDIO_QUEUEBUFFER_SIZE; ++i) {
        NSLog(@"buffer size with bitrate: %d", _codecCtx->bit_rate);
        if ((AudioQueueAllocateBufferWithPacketDescriptions(_audioQueue, 200401, 16, &_audioQueueBuffer[i]))!=noErr) {
            NSLog(@"Error: Could not allocate audio queue buffer");
            AudioQueueDispose(_audioQueue, YES);
            return false;
        }
    }
    
    // enable time_pitch
    UInt32 trueValue = 1;
    AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_EnableTimePitch, &trueValue, sizeof(trueValue));
    UInt32 timePitchAlgorithm = kAudioQueueTimePitchAlgorithm_Spectral; // supports rate and pitch
    AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_TimePitchAlgorithm, &timePitchAlgorithm, sizeof(timePitchAlgorithm));
    
    Float32 gain=1.0;
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, gain);
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Pitch, -1200);
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_PlayRate, 1.0);

    bufferDispatchQueue = dispatch_queue_create("com.kcmonkey.AudioBufferDispatchTask", NULL);
    
    return true;
}

void AudioDecoder::reset()
{
    dispatch_sync(bufferDispatchQueue, ^{
        _packetRingBuffer->flush();
    });
    startTime = 0;
    stop();
}

void AudioDecoder::setStartTime(float newStartTime)
{
    startTime = newStartTime;
}

AudioDecoder::~AudioDecoder()
{
    delete _packetRingBuffer;
}

bool AudioDecoder::feedPacket(AVPacket &packet)
{
    AT_FrameInfo frameInfo;
    frameInfo.pts = packet.pts;
    frameInfo.dts = packet.dts;
    frameInfo.duration = packet.duration;
    
    if (!_packetRingBuffer->isBufferAvailable(packet.size))
    {
        return false;
    }
    
    float ptsTime = convertRawTimeToSeconds(frameInfo.pts);
    
    dispatch_sync(bufferDispatchQueue, ^{
        if (ptsTime >= startTime)
            _packetRingBuffer->pushBack(packet.data, packet.size, frameInfo);
    });
    
    return true;
}

bool AudioDecoder::consumePacket(AudioQueueBufferRef inBuffer)
{
    if (_packetRingBuffer->isBufferEmpty())
    {
        NSLog(@"return since buffer is empty");
        return true;
    }
    inBuffer->mPacketDescriptionCount = 0;
    inBuffer->mAudioDataByteSize = 0;
    while (!_packetRingBuffer->isBufferEmpty() && (inBuffer->mPacketDescriptionCount < inBuffer->mPacketDescriptionCapacity)) {
        RingBufferDataRef<AT_FrameInfo> &frameRef = _packetRingBuffer->front();
        memcpy((uint8_t *)inBuffer->mAudioData + inBuffer->mAudioDataByteSize, frameRef.head, frameRef.size);
        inBuffer->mPacketDescriptions[inBuffer->mPacketDescriptionCount].mStartOffset = inBuffer->mAudioDataByteSize;
        inBuffer->mPacketDescriptions[inBuffer->mPacketDescriptionCount].mDataByteSize = frameRef.size ;
        inBuffer->mPacketDescriptions[inBuffer->mPacketDescriptionCount].mVariableFramesInPacket = _codecCtx->frame_size;
        inBuffer->mPacketDescriptionCount++;
        inBuffer->mAudioDataByteSize += (frameRef.size);
        dispatch_sync(bufferDispatchQueue, ^{
             _packetRingBuffer->popFront();
        });
    }
    
    if (AudioQueueEnqueueBuffer(_audioQueue, inBuffer, 0, NULL) != noErr)
        NSLog(@"Error: failed to enqueue buffer");
   

    return true;
}

float AudioDecoder::getCurrentTime()
{
    AudioQueueTimelineRef timeLine;
    OSStatus status = AudioQueueCreateTimeline(_audioQueue, &timeLine);
    if (status == noErr)
    {
        AudioTimeStamp timeStemp;
        AudioQueueGetCurrentTime(_audioQueue, NULL, &timeStemp, NULL);
        return timeStemp.mSampleTime / _codecCtx->sample_rate + startTime;
    }
    return  -1;
}

void AudioDecoder::InitAudioQueueBuffer()
{
    if (audioQueueInitilized)
        return;
    
    dispatch_async(dispatch_queue_create("com.kcmonkey.audioQueueStart", nullptr), ^{
        
        while (_packetRingBuffer->bufferCount() < 48)
        {
            NSLog(@"waiting audio packet buffer to be filled %d", _packetRingBuffer->bufferCount());
            usleep(40000);
        }
        
        for (int i = 0; i < AUDIO_QUEUEBUFFER_SIZE; ++i) {
            NSLog(@"calling consume packet from start");
            this->consumePacket(_audioQueueBuffer[i]);
        }
        
        audioQueueInitilized = true;
    });
}

void AudioDecoder::start()
{
    if(AudioQueueStart(_audioQueue, nil) != noErr)
    {
        NSLog(@"Error: cant start audio queue due to an error");
    }
    
    NSLog(@"audio queue started");
}

void AudioDecoder::stop()
{
    AudioQueueFlush(_audioQueue);
    AudioQueueStop(_audioQueue, true);
    audioQueueInitilized = false;
}

void AudioDecoder::pause()
{
    AudioQueuePause(_audioQueue);
}

void AudioDecoder::setVolume(float volume)
{
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, volume);
}

void AudioDecoder::setRate(float rate)
{
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_PlayRate, rate);
}

float AudioDecoder::convertRawTimeToSeconds(UInt64 rawTime)
{
    //return av_rescale_q(rawTime / AV_TIME_BASE, _context_time_base, AV_TIME_BASE_Q);
    return rawTime / (float)convertSecondsToRawTime(1);
}

UInt64 AudioDecoder::convertSecondsToRawTime(float secs)
{
    return av_rescale_q(secs * AV_TIME_BASE, AV_TIME_BASE_Q, _context_time_base);
}

void HandleOutputBuffer(void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    if(aqData!=nil)
    {
        AudioDecoder* weakRef = (AudioDecoder*)aqData;
        weakRef->consumePacket(inBuffer);
    }
}

