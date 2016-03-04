//
//  VideoDecoder.hpp
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 12/8/15.
//  Copyright © 2015 Cong Ku. All rights reserved.
//

#ifndef VideoDecoder_hpp
#define VideoDecoder_hpp

#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

extern "C" {
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libavcodec/avcodec.h"
#include "libavformat/avio.h"
};

#include "RingBuffer.hpp"

#include "PlayerSetting.hpp"

#define PACKET_BUFFER_SIZE 1024*1024*5 //5 Mbytes
//#define VIDEO_BUFFER_SIZE 1024*1024*20  //20 Mbytes


struct VT_FrameInfo {
    int64_t duration;
    int64_t dts;
    int64_t pts;
};

struct VTTimeRange {
    double start;
    double end;
    
    double getDuration() {return end - start;}
    bool isValid() {return end != -1 && start != -1;};
};

class VideoDecoder
{
public:
   // static VideoDecoder* NewVideoDecoder(AVFormatContext* formatCtx, int stream_n);
    bool init(AVFormatContext* formatCtx);
    void reset();
    bool createDepressSession();
    ~VideoDecoder();
    
    bool feedPacket(AVPacket &packet);
    bool consumePacket(bool forDisplay, bool noDelay);
    
    float convertRawTimeToSeconds(UInt64 rawTime);
    UInt64 convertSecondsToRawTime(float secs);
    
    AVCodecContext* _codecCtx;
    
    int streamNum;
    float frameInterval;
    float currentPTS;
    float decodingPTS;
    dispatch_queue_t bufferDispatchQueue;
    RingBuffer<VT_FrameInfo> *_packetRingBuffer;
    CVImageBufferRef currentImageBuffer;
    
    bool bufferReady = false;
    uint8_t* frameRGB_Buffer;

    VTTimeRange timeRange;
    double endTime;
    
private:
    AVRational _context_time_base;

#if HW_DECODING == 0
    //for software decoding
    AVCodecContext* _codecCtxDecoding;
    SwsContext *_sws_ctx = NULL;
    AVPacket pkt;
    AVFrame *frame;
    AVFrame *frameRGB;
    uint8_t dstPlane[921600];
#else
    
    CMVideoFormatDescriptionRef _formatDescription;
    VTDecompressionSessionRef _decompressSession;
#endif
    uint8_t __packetBuffer[PACKET_BUFFER_SIZE];
};

#if HW_DECODING == 1
void decompressionSessionCallback(void *decompressionOutputRefCon,
                                  void *sourceFrameRefCon,
                                  OSStatus status,
                                  VTDecodeInfoFlags infoFlags,
                                  CVImageBufferRef imageBuffer,
                                  CMTime presentationTimeStamp,
                                  CMTime presentationDuration);
#endif

CMFormatDescriptionRef CreateFormatDescriptionFromCodecData(uint32_t, int, int, const uint8_t*, int, uint32_t);


#endif /* VideoDecoder_hpp */
