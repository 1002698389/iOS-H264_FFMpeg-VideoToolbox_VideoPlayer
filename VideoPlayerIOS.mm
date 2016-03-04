//
//  VideoPlayerIOS.m
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 1/27/16.
//  Copyright © 2016 Cong Ku. All rights reserved.
//

#import "VideoPlayerIOS.h"

@implementation VideoPlayerIOS

@synthesize playerStatus = _playerStatus, playerStarted = _started, playback = _playback;

+ (NSHashTable *)allInstances {
    static NSHashTable *allInstances;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allInstances = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory];
        //initialize ffmpeg
        avformat_network_init();
        avcodec_register_all();
        av_register_all();
    });
    return allInstances;
}


+ (void)mute:(BOOL)mute
{
    for (VideoPlayerIOS* player in [VideoPlayerIOS allInstances])
    {
        [player setVolume:0 forTrack:nullptr];
    }
}

-(id)init
{
    if (self = [super init])
    {
        [[VideoPlayerIOS allInstances] addObject:self];
        _playerStatus = PZVIDEOSOURCE_STATE_UNKNOWN;

        _boundaryTime = 23;
        _lastBoundaryTimeReached = -1;
        _playbackRate = 1.0f;
        
#if TARGET_OS_IPHONE
        // Register for application lifecycle notifications
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
#endif
    }
    return self;
}

- (void)cleanup
{
    [self stop];
}

- (BOOL)isActive
{
    return false;
}

- (BOOL)load:(NSString *)path
{
    return [self load:path extraAudio:NULL loops:0];
}

- (BOOL)load:(NSString *)path extraAudio:(NSArray*)audioPaths loops:(NSUInteger)loops
{
    char* videoPath = (char*)[path UTF8String];
    char* audioPath = NULL;
    if (audioPaths.count > 0)
    {
        NSString* audioPathString = [audioPaths objectAtIndex:0];
        if (audioPathString)
            audioPath = (char*)[audioPathString UTF8String];
    }
    
    if (avformat_open_input(&_vFormatContext, videoPath, NULL, NULL) != 0)
    {
        av_log(NULL, AV_LOG_ERROR, "Error: Cannot open file.");
        _playerStatus = PZVIDEOSOURCE_STATE_ERROR;
        return false;
    }
    
    avformat_find_stream_info(_vFormatContext, nullptr);
    
    
    _video_audio_samefile = (audioPath == NULL);
    char* _audioPath = _video_audio_samefile ? videoPath : audioPath;
    
    if (!_video_audio_samefile)
    {
        if (avformat_open_input(&_aFormatContext, _audioPath, NULL, NULL) != 0)
        {
            av_log(NULL, AV_LOG_ERROR, "Error: Cannot open file.");
            _playerStatus = PZVIDEOSOURCE_STATE_ERROR;
            return false;
        }
        avformat_find_stream_info(_aFormatContext, nullptr);
    }
    
    
    _videoDecoder.init(_vFormatContext);
    if (!_audioDecoder.init(_video_audio_samefile ? _vFormatContext : _aFormatContext))
    {
        _videoOnly = true;
    }
    
    _playerStatus = PZVIDEOSOURCE_STATE_LOADING;
    _seekTrigger = false;
    _seekTime = 0;
    
    _videoDuration = av_rescale_q(_vFormatContext->duration / AV_TIME_BASE, _vFormatContext->streams[_videoDecoder.streamNum]->time_base, AV_TIME_BASE_Q);
    NSLog(@"video duration: %f", _videoDuration);
    
    _packetsLoadingQueue = dispatch_queue_create("com.kcmonkey.PacketsLoadingQueue", nullptr);
    _packetsConsumingQueue = dispatch_queue_create("com.kcmonkey.PacketsConsumingQueue", nullptr);
    
    _started = true;

    _audioPacketConsumed = true;
    _videoPacketConsumed = true;
    _packetConsumed = true;

    dispatch_async(_packetsConsumingQueue, ^{
        [self startConsumingVideoPacket];
    });

    dispatch_async(_packetsLoadingQueue, ^{
        [self startLoadingPackets];
    });
    
    return true;
}

- (BOOL)setVolume:(float)volume forTrack:(NSString *)url
{
    _audioDecoder.setVolume(volume);
    return true;
}

- (void)play:(float)rate
{
    if (!_started)
    {
        _audioPacketConsumed = true;
        _videoPacketConsumed = true;
        _packetConsumed = true;
        
        _started = true;
        
        dispatch_async(_packetsConsumingQueue, ^{
            [self startConsumingVideoPacket];
        });
        
        dispatch_async(_packetsLoadingQueue, ^{
            [self startLoadingPackets];
        });

        
        if (!_videoOnly)
        {
            _audioDecoder.InitAudioQueueBuffer();
            _audioDecoder.start();
        }
        
        _playback = true;
        
        _videoTimer.start(0);
    }
    else
    {
        if (_videoOnly)
        {
            _videoTimer.resume();
        }
        else {
            _audioDecoder.InitAudioQueueBuffer();
            _audioDecoder.start();
        }
        
        _playback = true;
    }
    
    if (_playerStatus == PZVIDEOSOURCE_STATE_SEGMENT_ENDED)
    {
        _lastBoundaryTimeReached = -1;
        _boundaryTime = -1;
    }
}

- (void)setPlaybackRate:(float)playbackRate
{
    _playbackRate = playbackRate;
    if (_videoOnly)
    {
        _videoTimer.setRate(playbackRate);
    }
    else
    {
        _audioDecoder.setRate(playbackRate);
    }
}

- (void)pause
{
    if (_videoOnly)
    {
        _videoTimer.pause();
    }
    else
    {
        _audioDecoder.pause();
    }
    
    _playback = false;
}

- (void)stop
{
    if (_videoOnly)
    {
        _videoTimer.pause();
    }
    else
    {
        _audioDecoder.pause();
    }
    _started = false;
    _playback = false;
}

- (void)step:(int)count
{
    float dealtTime = count * _videoDecoder.frameInterval;
    [self seekTo:[self getCurrentPlayTime] + dealtTime];
}

- (void)seekTo:(double)seekTime
{
    if (_seekTrigger == false)
    {
        NSLog(@"seek pressed");
        
        if (seekTime >= _boundaryTime) _boundaryTime = -1;
        
        _seekTime = seekTime;
        _seekTrigger = true;
        
        int seekFlags =  AVSEEK_FLAG_BACKWARD | AVSEEK_FLAG_FRAME;
        int64_t videoSeekTime = _videoDecoder.convertSecondsToRawTime(_seekTime);
        av_seek_frame(_vFormatContext, _videoDecoder.streamNum, videoSeekTime, seekFlags);
        
        _videoDecoder.reset();
        
        if (_videoOnly)
        {
            _videoTimer.setCurrentTime(_seekTime);
            _videoTimer.pause();
        }
        else
        {
            if (!_video_audio_samefile)
            {
                int64_t audioSeekTime = _audioDecoder.convertSecondsToRawTime(_seekTime);
                av_seek_frame(_aFormatContext, _audioDecoder.streamNum, audioSeekTime, seekFlags);
            }
            _audioDecoder.reset();
            _audioDecoder.setStartTime(_seekTime);
            NSLog(@"new seek time: %f", _seekTime);
            NSLog(@"current audio time after seek: %f", [self getCurrentPlayTime]);
            _audioDecoder.InitAudioQueueBuffer();
        }
        
        _packetConsumed = true;
        _audioPacketConsumed = true;
        _videoPacketConsumed = true;
        
        _playerStatus = PZVIDEOSOURCE_STATE_LOADING;
        NSLog(@"start seeking");
        
        while (_seekTrigger)
        {
            [self readPacket];
            
            if (_videoDecoder.decodingPTS != -1 && _videoDecoder.decodingPTS < [self getCurrentPlayTime])
            {
                _videoDecoder.consumePacket(false, false);
            }
            else {
                NSLog(@"current video pts: %f", _videoDecoder.decodingPTS);
                if (_videoDecoder.decodingPTS != -1 && _videoDecoder.decodingPTS >= [self getCurrentPlayTime])
                {
                    NSLog(@"seeking complete");
                    _videoDecoder.consumePacket(true, true);
                    _playerStatus = PZVIDEOSOURCE_STATE_READYTOPLAY;
                    _playback = false;
                    _seekTrigger = false;
                    NSLog(@"consumed one more for seek");
                }
                
                NSLog(@"current video pts: %f", _videoDecoder.decodingPTS);
                NSLog(@"current audio time: %f", [self getCurrentPlayTime]);
            }
        }

    }
}

- (void)rewindPlayer
{
    _playerStatus = PZVIDEOSOURCE_STATE_SEGMENT_ENDED;
    
    // Mark last reached boundary position
    _lastBoundaryTimeReached = _boundaryTime;
    [self seekTo:_boundaryTime];
}

- (void)startLoadingPackets
{
    while (_started) {
        int thread_wait_time = 40000;
        
        if (!_seekTrigger)
        {
            thread_wait_time = [self readPacket] ? 0 : 40000;
        }
        
        usleep(thread_wait_time);
    }

}

- (bool)readPacket
{
    bool packetConsumed = false;
    
    if (_video_audio_samefile) {
        if (_packetConsumed)
        {
            if (av_read_frame(_vFormatContext, &_packet) >= 0)
            {
                if (_packet.stream_index == _videoDecoder.streamNum)
                {
                    _packetConsumed = false;
                    if (_videoDecoder.feedPacket(_packet))
                    {
                        _packetConsumed = true;
                        av_free_packet(&_packet);
                    }
                }
                else if (!_videoOnly && _packet.stream_index == _audioDecoder.streamNum)
                {
                    _packetConsumed = false;
                    if (_audioDecoder.feedPacket(_packet))
                    {
                        _packetConsumed = true;
                        av_free_packet(&_packet);
                    }
                }
                else
                {
                    av_free_packet(&_packet);
                }
            }
        }
        else
        {
            if (_packet.stream_index == _videoDecoder.streamNum)
            {
                if (_videoDecoder.feedPacket(_packet))
                {
                    _packetConsumed = true;
                    av_free_packet(&_packet);
                }
            }
            else if (_packet.stream_index == _audioDecoder.streamNum)
            {
                if (_audioDecoder.feedPacket(_packet))
                {
                    _packetConsumed = true;
                    av_free_packet(&_packet);
                }
            }
        }
        
        packetConsumed = _packetConsumed;
    }
    else
    {
        //load audioPacket
        if (!_videoOnly) {
            if (_audioPacketConsumed)
            {
                if (av_read_frame(_aFormatContext, &_audioPacket) >= 0) {
                    if (_audioPacket.stream_index == _audioDecoder.streamNum) {
                        _audioPacketConsumed = false;
                        if (_audioDecoder.feedPacket(_audioPacket))
                        {
                            _audioPacketConsumed = true;
                            av_free_packet(&_audioPacket);
                        }
                    }
                    else
                    {
                        av_free_packet(&_audioPacket);
                    }
                }
            }
            else if (_audioDecoder.feedPacket(_audioPacket))
            {
                _audioPacketConsumed = true;
                av_free_packet(&_audioPacket);
            }
        }
        
        //load videoPacket
        if (_videoPacketConsumed)
        {
            if (av_read_frame(_vFormatContext, &_videoPacket) >= 0)
            {
                if (_videoPacket.stream_index == _videoDecoder.streamNum)
                {
                    _videoPacketConsumed = false;
                    if (_videoDecoder.feedPacket(_videoPacket))
                    {
                        _videoPacketConsumed = true;
                        av_free_packet(&_videoPacket);
                    }
                }
                else
                {
                    av_free_packet(&_videoPacket);
                }
            }
        }
        else if (_videoDecoder.feedPacket(_videoPacket))
        {
            _videoPacketConsumed = true;
            av_free_packet(&_videoPacket);
        }
        
        packetConsumed = _videoPacketConsumed || _audioPacketConsumed;
    }
    
    if (_playerStatus == PZVIDEOSOURCE_STATE_LOADING && !_seekTrigger && (_videoDecoder.timeRange.getDuration() > 2 || _videoDecoder.timeRange.end >= _videoDecoder.endTime))
    {
        _playerStatus = PZVIDEOSOURCE_STATE_READYTOPLAY;
    }
    
    return packetConsumed;
}

- (void)startConsumingVideoPacket
{
    while (_started) {
        if (_playerStatus != PZVIDEOSOURCE_STATE_LOADING)
        {
            //NSLog(@"for display, current decoding pts: %f", _videoDecoder.decodingPTS);
            if (_videoDecoder.currentPTS < [self getCurrentPlayTime]) {
                _videoDecoder.consumePacket(true, false);
            }
        }
        
        if (_boundaryTime > 0 && _videoDecoder.currentPTS >= _boundaryTime)
        {
            [self rewindPlayer];
        }
        
        usleep(_playerStatus == PZVIDEOSOURCE_STATE_LOADING ? 0 : 2000);
    }

}

- (float)getCurrentPlayTime
{
    return _videoOnly ? _videoTimer.getCurrentTime() : _audioDecoder.getCurrentTime();
}

- (double)duration
{
    return _videoDecoder.endTime;
}

- (double)position
{
    if (_playerStatus == PZVIDEOSOURCE_STATE_SEGMENT_ENDED)
    {
        return _lastBoundaryTimeReached;
    }
    else if (_playerStatus != PZVIDEOSOURCE_STATE_LOADING)
    {
        return _videoDecoder.currentPTS;
    }
    
    return _seekTime;
}

- (void)draw:(AAPLEAGLLayer *)_gllayer
{
    dispatch_sync(_videoDecoder.bufferDispatchQueue, ^{
        if (_videoDecoder.currentImageBuffer)
            NSLog(@"frame size: %d, %d", _videoDecoder._codecCtx->width, _videoDecoder._codecCtx->height);
            [_gllayer displayPixelBuffer:_videoDecoder.currentImageBuffer width:_videoDecoder._codecCtx->width height:_videoDecoder._codecCtx->height];
    });
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {

}

@end
