//
//  VideoDecoder.cpp
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 12/8/15.
//  Copyright © 2015 Cong Ku. All rights reserved.
//

#include "VideoDecoder.hpp"

bool VideoDecoder::init(AVFormatContext* formatCtx)
{
    currentPTS = -1;
    decodingPTS = -1;
    
    //create buffers
    _packetRingBuffer = new RingBuffer<VT_FrameInfo>(__packetBuffer, PACKET_BUFFER_SIZE);
    
    streamNum = av_find_best_stream(formatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (streamNum < 0) {
        return false;
    }
    
    //create decode context
    _codecCtx = formatCtx->streams[streamNum]->codec;
    frameInterval = 1.0 / ((float)_codecCtx->framerate.num / (float)_codecCtx->framerate.den);
    NSLog(@"frame interval: %f", frameInterval);
    
    if (!createDepressSession())
    {
        return false;
    }

    _context_time_base = formatCtx->streams[streamNum]->time_base;
    
    timeRange.start = -1;
    timeRange.end = -1;
    endTime = formatCtx->duration / 1000000.0;
    NSLog(@"Video Duration in secs: %f", endTime);
    
    bufferDispatchQueue = dispatch_queue_create("com.kcmonkey.VideoBufferDispatchTask", NULL);
    
    return true;
}

void VideoDecoder::reset()
{
    dispatch_sync(bufferDispatchQueue, ^{
        _packetRingBuffer->flush();
        currentPTS = -1;
        decodingPTS = -1;
        CVBufferRelease(currentImageBuffer);
        currentImageBuffer = NULL;
        timeRange.start = -1;
        timeRange.end = -1;
    });
#if HW_DECODING == 1
    createDepressSession();
#else
    avcodec_flush_buffers(_codecCtxDecoding);
#endif
}


VideoDecoder::~VideoDecoder()
{
#if HW_DECODING == 0
    av_free(frame);
    av_free(frameRGB);
#else
    if(_decompressSession) {
        VTDecompressionSessionInvalidate(_decompressSession);
        CFRelease(_decompressSession);
        _decompressSession = NULL;
    }
#endif
    
    delete _packetRingBuffer;

}

bool VideoDecoder::feedPacket(AVPacket &packet)
{
    VT_FrameInfo frameInfo;
    frameInfo.pts = packet.pts;
    frameInfo.dts = packet.dts;
    frameInfo.duration = packet.duration;
    
    if (_packetRingBuffer->isBufferEmpty())
    {
        decodingPTS = convertRawTimeToSeconds(packet.pts);
    }
    
    if (!_packetRingBuffer->isBufferAvailable(packet.size))
    {
        //NSLog(@"buffer not available");
        return false;
    }
    
    if(packet.size > 0 && packet.size != 12)
    {
        dispatch_sync(bufferDispatchQueue, ^{
            this->_packetRingBuffer->pushBack(packet.data, packet.size, frameInfo);
            this->timeRange.end = convertRawTimeToSeconds(frameInfo.pts);
        });
    }
 
    return true;
}

bool VideoDecoder::consumePacket(bool forDisplay, bool noDelay)
{
    if (_packetRingBuffer->isBufferEmpty())
    {
        return false;
    }
    
    RingBufferDataRef<VT_FrameInfo> &frameRef = _packetRingBuffer->front();
    
#if HW_DECODING == 1
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;

    if (CMBlockBufferCreateWithMemoryBlock(NULL, frameRef.head, frameRef.size, kCFAllocatorNull, NULL, 0, frameRef.size, 0, &blockBuffer) != noErr)
    {
        return false;
    }
    const size_t sampleSize = frameRef.size;

    CMSampleTimingInfo frameTimingInfo;
    int _timeInSecsDominator = (int)convertSecondsToRawTime(1);
    frameTimingInfo.decodeTimeStamp = CMTimeMake(frameRef.userData.dts, _timeInSecsDominator);
    frameTimingInfo.duration = CMTimeMake(frameRef.userData.duration, _timeInSecsDominator);
    frameTimingInfo.presentationTimeStamp = CMTimeMake(frameRef.userData.pts, _timeInSecsDominator);
    
    //decodingPTS = CMTimeGetSeconds(frameTimingInfo.presentationTimeStamp);
    
    if (CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, true, NULL, NULL, _formatDescription, 1, 1, &frameTimingInfo, 1, &sampleSize, &sampleBuffer) != noErr)
    {
        NSLog(@"erroe when create samplebuffer");
    }
    
    //decode buffer and add to vieoRingBuffer
    VTDecodeFrameFlags flags = forDisplay ? 0 : (kVTDecodeFrame_DoNotOutputFrame);
    VTDecodeInfoFlags flagOut;
    VTDecompressionSessionDecodeFrame(_decompressSession, sampleBuffer, flags,
                                      &sampleBuffer, &flagOut);
    
    CFRelease(sampleBuffer);
    CFRelease(blockBuffer);
    
    dispatch_sync(bufferDispatchQueue, ^{
        if (!this->_packetRingBuffer->isBufferEmpty()) {
            this->_packetRingBuffer->popFront();
            if (!this->_packetRingBuffer->isBufferEmpty())
            {
                RingBufferDataRef<VT_FrameInfo> &frameRef = this->_packetRingBuffer->front();
                this->timeRange.start = convertRawTimeToSeconds(frameRef.userData.pts);
            }
            else
            {
                this->timeRange.start = -1;
            }
        }
    });
#else
    pkt.data = frameRef.head;
    pkt.size = frameRef.size;
    //decodingPTS = convertRawTimeToSeconds(frameRef.userData.pts);
    int got_picture;
    if (pkt.data) {
        avcodec_decode_video2(_codecCtxDecoding, frame, &got_picture, &pkt);
    }
    
    if (noDelay)
    {
        pkt.data = nullptr;
        pkt.size = 0;
        avcodec_decode_video2(_codecCtxDecoding, frame, &got_picture, &pkt);
    }
    
    size_t srcPlaneSize = frame->linesize[1]*frame->height/2;
    size_t dstPlaneSize = srcPlaneSize *2;
    assert(frame->linesize[1] == frame->linesize[2]);
    
    for(size_t i = 0; i<srcPlaneSize; i++){
        // These might be the wrong way round.
        dstPlane[2*i  ] = frame->data[1][i];
        dstPlane[2*i+1] = frame->data[2][i];
    }
    
    CVPixelBufferRef outputPixelBuffer = nil;
    
    NSDictionary *pixelBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSDictionary dictionary], kCVPixelBufferIOSurfacePropertiesKey,
                                           nil];
    
    int ret = CVPixelBufferCreate(kCFAllocatorDefault, frame->width, frame->height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, (__bridge CFDictionaryRef)pixelBufferAttributes, &outputPixelBuffer);
    
    CVPixelBufferLockBaseAddress(outputPixelBuffer, 0);
    
    uint8_t* addressY = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(outputPixelBuffer, 0);
    uint8_t* addressUV = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(outputPixelBuffer, 1);
    
    memcpy(addressY, frame->data[0], frame->width * frame->height);
    memcpy(addressUV, dstPlane, dstPlaneSize);
    
    CVPixelBufferUnlockBaseAddress(outputPixelBuffer, 0);
    
    dispatch_sync(bufferDispatchQueue, ^{
        
        if (ret != -1)
        {
            currentPTS = decodingPTS;
            CVBufferRelease(currentImageBuffer);
            currentImageBuffer = outputPixelBuffer;
        }
        
        if (!this->_packetRingBuffer->isBufferEmpty()) {
            this->_packetRingBuffer->popFront();
        }
    });
#endif
    if (!_packetRingBuffer->isBufferEmpty())
    {
        RingBufferDataRef<VT_FrameInfo> &nextFrameRef = _packetRingBuffer->front();
        decodingPTS = convertRawTimeToSeconds(nextFrameRef.userData.pts);
    }
    
    return true;
}

bool VideoDecoder::createDepressSession()
{
#if HW_DECODING == 1
    //get video format description
    _formatDescription = CreateFormatDescriptionFromCodecData(kCMVideoCodecType_H264, _codecCtx->width, _codecCtx->height, _codecCtx->extradata, _codecCtx->extradata_size, 0);

    if (_decompressSession)
    {
        VTDecompressionSessionInvalidate(_decompressSession);
        CFRelease(_decompressSession);
    }
    _decompressSession = NULL;
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionCallback;
    callBackRecord.decompressionOutputRefCon = this;
    NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                                      [NSNumber numberWithBool:YES],
                                                      (id)kCVPixelBufferOpenGLESCompatibilityKey,
                                                      nil];
    OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDescription, NULL,
                                                    (__bridge CFDictionaryRef)(destinationImageBufferAttributes),
                                                    &callBackRecord, &_decompressSession);
    NSLog(@"Video Decompress session create: %@", (status == noErr) ? @"Success" : @"Failed");
#else
    AVCodec* codec = avcodec_find_decoder(_codecCtx->codec_id);
    if (avcodec_open2(_codecCtx, codec, nil) < 0)
        return false;

    _codecCtxDecoding = avcodec_alloc_context3(codec);
    avcodec_copy_context(_codecCtxDecoding, _codecCtx);
    
    _sws_ctx = sws_getContext(_codecCtx->width,
                              _codecCtx->height,
                              _codecCtx->pix_fmt,
                              _codecCtx->width,
                              _codecCtx->height,
                              PIX_FMT_RGB24,
                              SWS_BILINEAR,
                              NULL,
                              NULL,
                              NULL
                              );
    
    
    frame = av_frame_alloc();
    frameRGB = av_frame_alloc();
    int numBytes = avpicture_get_size(PIX_FMT_RGB24, _codecCtxDecoding->width, _codecCtxDecoding->height);
    frameRGB_Buffer = (uint8_t*)av_malloc(numBytes * sizeof(uint8_t));
    avpicture_fill((AVPicture*)frameRGB, frameRGB_Buffer, PIX_FMT_RGB24, _codecCtxDecoding->width, _codecCtxDecoding->height);
    av_init_packet(&pkt);
    
    avcodec_open2(_codecCtxDecoding, codec, nullptr);

#endif

    return true;
}

#pragma --mark Video Depression Callback Funcition
#if HW_DECODING == 1
void decompressionSessionCallback(void *decompressionOutputRefCon,
                                  void *sourceFrameRefCon,
                                  OSStatus status,
                                  VTDecodeInfoFlags infoFlags,
                                  CVImageBufferRef imageBuffer,
                                  CMTime presentationTimeStamp,
                                  CMTime presentationDuration)
{
    //do something with frame buffer
    VideoDecoder* weakRef = (VideoDecoder*)decompressionOutputRefCon;
    
    dispatch_sync(weakRef->bufferDispatchQueue, ^{
        if (status == noErr)
        {
            weakRef->currentPTS = CMTimeGetSeconds(presentationTimeStamp);
            CVBufferRelease(weakRef->currentImageBuffer);
            weakRef->currentImageBuffer = CVBufferRetain(imageBuffer);
        }
    });
}
#endif

float VideoDecoder::convertRawTimeToSeconds(UInt64 rawTime)
{
    //return av_rescale_q(rawTime / AV_TIME_BASE, _context_time_base, AV_TIME_BASE_Q);
    return rawTime / (float)convertSecondsToRawTime(1);
}

UInt64 VideoDecoder::convertSecondsToRawTime(float secs)
{
    return av_rescale_q(secs * AV_TIME_BASE, AV_TIME_BASE_Q, _context_time_base);
}


#pragma --mark Video Description Generation helper functions

static void dict_set_string(CFMutableDictionaryRef dict, CFStringRef key, const char * value)
{
    CFStringRef string;
    string = CFStringCreateWithCString(NULL, value, kCFStringEncodingASCII);
    CFDictionarySetValue(dict, key, string);
    CFRelease(string);
}

static void dict_set_boolean(CFMutableDictionaryRef dict, CFStringRef key, BOOL value)
{
    CFDictionarySetValue(dict, key, value ? kCFBooleanTrue: kCFBooleanFalse);
}


static void dict_set_object(CFMutableDictionaryRef dict, CFStringRef key, CFTypeRef *value)
{
    CFDictionarySetValue(dict, key, value);
}

static void dict_set_data(CFMutableDictionaryRef dict, CFStringRef key, uint8_t * value, uint64_t length)
{
    CFDataRef data;
    data = CFDataCreate(NULL, value, (CFIndex)length);
    CFDictionarySetValue(dict, key, data);
    CFRelease(data);
}

static void dict_set_i32(CFMutableDictionaryRef dict, CFStringRef key,
                         int32_t value)
{
    CFNumberRef number;
    number = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
    CFDictionarySetValue(dict, key, number);
    CFRelease(number);
}

CMFormatDescriptionRef CreateFormatDescriptionFromCodecData(uint32_t format_id, int width, int height, const uint8_t *extradata, int extradata_size, uint32_t atom)
{
    CMFormatDescriptionRef fmt_desc = NULL;
    OSStatus status;
    
    CFMutableDictionaryRef par = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef atoms = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef extensions = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    /* CVPixelAspectRatio dict */
    dict_set_i32(par, CFSTR ("HorizontalSpacing"), 0);
    dict_set_i32(par, CFSTR ("VerticalSpacing"), 0);
    /* SampleDescriptionExtensionAtoms dict */
    dict_set_data(atoms, CFSTR ("avcC"), (uint8_t *)extradata, extradata_size);
    
    /* Extensions dict */
    dict_set_string(extensions, CFSTR ("CVImageBufferChromaLocationBottomField"), "left");
    dict_set_string(extensions, CFSTR ("CVImageBufferChromaLocationTopField"), "left");
    dict_set_boolean(extensions, CFSTR("FullRangeVideo"), FALSE);
    dict_set_object(extensions, CFSTR ("CVPixelAspectRatio"), (CFTypeRef *) par);
    dict_set_object(extensions, CFSTR ("SampleDescriptionExtensionAtoms"), (CFTypeRef *) atoms);
    status = CMVideoFormatDescriptionCreate(NULL, format_id, width, height, extensions, &fmt_desc);
    
    CFRelease(extensions);
    CFRelease(atoms);
    CFRelease(par);
    
    if (status == 0)
        return fmt_desc;
    else
        return NULL;
}
