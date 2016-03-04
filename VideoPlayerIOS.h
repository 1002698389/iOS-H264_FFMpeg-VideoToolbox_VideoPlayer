//
//  VideoPlayerIOS.h
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 1/27/16.
//  Copyright © 2016 Cong Ku. All rights reserved.
//

#import <Foundation/Foundation.h>
#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#endif

#import <CoreMedia/CoreMedia.h>

extern "C" {
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libavcodec/avcodec.h"
#include "libavformat/avio.h"
};

#include "VideoDecoder.hpp"
#include "AudioDecoder.hpp"

#include "VideoTimer.hpp"

#import "AAPLEAGLLayer.h"

#include "PlayerSetting.hpp"

typedef enum PZVideoSourceState {
    PZVIDEOSOURCE_STATE_UNKNOWN = 0,
    PZVIDEOSOURCE_STATE_LOADING,
   	PZVIDEOSOURCE_STATE_READYTOPLAY,
    PZVIDEOSOURCE_STATE_SEGMENT_ENDED,
    PZVIDEOSOURCE_STATE_ENDED,
    PZVIDEOSOURCE_STATE_ERROR,
} PZVideoSourceState;

@interface VideoPlayerIOS : NSObject
{
    AVFormatContext* _vFormatContext;
    AVFormatContext* _aFormatContext;
    VideoDecoder _videoDecoder;
    AudioDecoder _audioDecoder;
    
    PZVideoSourceState _playerStatus;
    
    bool _started;
    bool _playback;
    
    bool _videoOnly;
    bool _video_audio_samefile;
    
    bool _seekTrigger;
    double _seekTime;
    VideoTimer _videoTimer;
    
    float _videoDuration;
    //TimeRange _loadedTimeRange;
    
    dispatch_queue_t _packetsLoadingQueue;
    dispatch_queue_t _packetsConsumingQueue;
    
    AVPacket _packet;
    bool _packetConsumed;
    
    AVPacket _videoPacket;
    AVPacket _audioPacket;
    bool _audioPacketConsumed;
    bool _videoPacketConsumed;
}

@property (nonatomic, readonly) PZVideoSourceState playerStatus;
@property (nonatomic, readonly) bool playerStarted;
@property (nonatomic, readonly) bool playback;
@property (nonatomic, readonly) float playbackRate;

@property (assign, nonatomic) double boundaryTime;
@property (readonly, nonatomic) double lastBoundaryTimeReached;
@property (readonly, nonatomic) double duration;
@property (readonly, nonatomic) double position;

+ (void)mute:(BOOL)mute; // mute all videos

- (void)cleanup;

- (BOOL)isActive;
- (BOOL)load:(NSString *)path;
- (BOOL)load:(NSString *)path extraAudio:(NSArray*)audioPaths loops:(NSUInteger)loops;
- (BOOL)setVolume:(float)volume forTrack:(NSString *)url;

- (void)play:(float)rate;
- (void)pause;
- (void)step:(int)count;
- (void)stop;

- (void)seekTo:(double)seekTime;

- (void)draw:(AAPLEAGLLayer*) _gllayer;

- (float)getCurrentPlayTime;

@end
