//
//  VideoPlayer.hpp
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 1/7/16.
//  Copyright © 2016 Cong Ku. All rights reserved.
//

#ifndef VideoPlayer_hpp
#define VideoPlayer_hpp

#import <UIKit/UIKit.h>
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

enum VIDEO_PLAYER_STATUS
{
    VIDEO_PLAYER_UNKNOWN = 0,
    VIDEO_PLAYER_LOADING,
    VIDEO_PLAYER_READY,
    VIDEO_PLAYER_PLAYING,
    VIDEO_PLAYER_PAUSED,
    VIDEO_PLAYER_SEEKING,
    VIDEO_PLAYER_ERROR
};

typedef struct{
    float start;
    float end;
} TimeRange;


class VideoPlayer
{
private:
    AVFormatContext* _vFormatContext;
    AVFormatContext* _aFormatContext;
    VideoDecoder _videoDecoder;
    AudioDecoder _audioDecoder;

    VIDEO_PLAYER_STATUS _playerStatus;
    
    bool _videoOnly;
    bool _video_audio_samefile;
    
    bool _seekTrigger;
    float _seekTime;
    VideoTimer _videoTimer;
    
    float _videoDuration;
    TimeRange _loadedTimeRange;
    
    dispatch_queue_t _packetsLoadingQueue;
    dispatch_queue_t _packetsConsumingQueue;
    
    AVPacket _packet;
    bool _packetConsumed;
    
    AVPacket _videoPacket;
    AVPacket _audioPacket;
    bool _audioPacketConsumed;
    bool _videoPacketConsumed;
public:
    static VideoPlayer* CreateNewPlayer(char *videoPath, char *audioPath);
    
    bool init(char *videoPath, char *audipPath);
    
    void setRate(float rate);
    
    void start();
    void stop();
    void resume();
    void pause();
    void seek(float time);
    
    void startLoadingPackets();
    void startConsumingVideoPacket();
    
    float getCurrentPlayTime();
    VIDEO_PLAYER_STATUS getCurrentStatue();
    
    void draw(AAPLEAGLLayer* _gllayer);
    GLint getCurrentTextureContext();
};

#endif /* VideoPlayer_hpp */
