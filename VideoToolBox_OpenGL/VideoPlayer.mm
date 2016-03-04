//
//  VideoPlayer.cpp
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 1/7/16.
//  Copyright © 2016 Cong Ku. All rights reserved.
//

#include "VideoPlayer.hpp"

VideoPlayer* VideoPlayer::CreateNewPlayer(char *videoPath, char *audioPath)
{
    VideoPlayer *_player = new VideoPlayer();
    if (_player && _player->init(videoPath, audioPath)) {
        return _player;
    }
    return nullptr;
}

bool VideoPlayer::init(char *videoPath, char *audioPath)
{    
    _playerStatus = VIDEO_PLAYER_LOADING;
    avformat_network_init();
    avcodec_register_all();
    av_register_all();
    
    if (avformat_open_input(&_vFormatContext, videoPath, NULL, NULL) != 0)
    {
        av_log(NULL, AV_LOG_ERROR, "Error: Cannot open file.");
        _playerStatus = VIDEO_PLAYER_ERROR;
        return false;
    }
    
    avformat_find_stream_info(_vFormatContext, nullptr);
    
    _video_audio_samefile = audioPath == NULL;
    char* _audioPath = _video_audio_samefile ? videoPath : audioPath;
    
    if (!_video_audio_samefile)
    {
        if (avformat_open_input(&_aFormatContext, _audioPath, NULL, NULL) != 0)
        {
            av_log(NULL, AV_LOG_ERROR, "Error: Cannot open file.");
            _playerStatus = VIDEO_PLAYER_ERROR;
            return false;
        }
        avformat_find_stream_info(_aFormatContext, nullptr);
    }
    
    
    _videoDecoder.init(_vFormatContext);
    if (!_audioDecoder.init(_video_audio_samefile ? _vFormatContext : _aFormatContext))
    {
        _videoOnly = true;
    }
    
    _playerStatus = VIDEO_PLAYER_READY;
    _seekTrigger = false;
    _seekTime = 0;
    
    _videoDuration = av_rescale_q(_vFormatContext->duration / AV_TIME_BASE, _vFormatContext->streams[_videoDecoder.streamNum]->time_base, AV_TIME_BASE_Q);
    NSLog(@"video duration: %f", _videoDuration);
    
    _packetsLoadingQueue = dispatch_queue_create("com.kcmonkey.PacketsLoadingQueue", nullptr);
    _packetsConsumingQueue = dispatch_queue_create("com.kcmonkey.PacketsConsumingQueue", nullptr);
    
    setRate(1.0f);
    
    return true;
}

void VideoPlayer::setRate(float rate)
{
    if (_videoOnly)
    {
        _videoTimer.setRate(rate);
    }
    else
    {
        _audioDecoder.setRate(rate);
    }
}

void VideoPlayer::start()
{
    _audioPacketConsumed = true;
    _videoPacketConsumed = true;
    _packetConsumed = true;
    dispatch_async(_packetsLoadingQueue, ^{
        this->startLoadingPackets();
    });
    
    dispatch_async(_packetsConsumingQueue, ^{
        this->startConsumingVideoPacket();
    });
    
    if (!_videoOnly)
    {
        _audioDecoder.InitAudioQueueBuffer();
        _audioDecoder.start();
    }
    
    _playerStatus = VIDEO_PLAYER_PLAYING;
    
    _videoTimer.start(0);
    
}

void VideoPlayer::stop()
{
    
}

void VideoPlayer::resume()
{
    if (_videoOnly)
    {
        _videoTimer.resume();
    }
    else {
        _audioDecoder.start();
    }
    
    _playerStatus = VIDEO_PLAYER_PLAYING;
}

void VideoPlayer::pause()
{
    if (_videoOnly)
    {
        _videoTimer.pause();
    }
    else
    {
        _audioDecoder.pause();
    }
    _playerStatus = VIDEO_PLAYER_PAUSED;
}

void VideoPlayer::seek(float time)
{
    if (_seekTrigger == false && _playerStatus != VIDEO_PLAYER_SEEKING)
    {
        _seekTime = time;
        _seekTrigger = true;
    }
}

void VideoPlayer::startLoadingPackets()
{
    while (true) {
        int thread_wait_time = 0;
        
        if (!_seekTrigger)
        {
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
                                _loadedTimeRange.end = _videoDecoder.convertRawTimeToSeconds(_packet.pts);
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
                
                thread_wait_time = _packetConsumed ? 0 : 40000;
 
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
                
                thread_wait_time = _videoPacketConsumed || _audioPacketConsumed ? 0 : 40000;
            }
        }
        else
        {
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
                _audioDecoder.InitAudioQueueBuffer();
            }
            
            _packetConsumed = true;
            _audioPacketConsumed = true;
            _videoPacketConsumed = true;
            
            _seekTrigger = false;
            _playerStatus = VIDEO_PLAYER_SEEKING;
            thread_wait_time = 0;
        }
        
        usleep(thread_wait_time);
    }
}

void VideoPlayer::startConsumingVideoPacket()
{
    while (true) {
        if (_playerStatus == VIDEO_PLAYER_SEEKING)
        {
            if (_videoDecoder.decodingPTS != -1 && _videoDecoder.decodingPTS < getCurrentPlayTime())
            {
                _videoDecoder.consumePacket(false, false);
            }
            else {
                NSLog(@"seeking complete");
                NSLog(@"current video pts: %f", _videoDecoder.decodingPTS);
                if (_videoDecoder.decodingPTS != -1 && _videoDecoder.decodingPTS >= getCurrentPlayTime())
                {
                    _videoDecoder.consumePacket(true, true);
                    _playerStatus = VIDEO_PLAYER_PAUSED;
                }
                NSLog(@"current video pts: %f", _videoDecoder.decodingPTS);
                NSLog(@"current audio time: %f", getCurrentPlayTime());
            }
        }
        else
        {
            //NSLog(@"for display, current decoding pts: %f", _videoDecoder.decodingPTS);
            if (_videoDecoder.currentPTS < getCurrentPlayTime()) {
                _videoDecoder.consumePacket(true, false);
            }
        }
        
        usleep(_playerStatus == VIDEO_PLAYER_SEEKING ? 0 : 2000);
    }
}

float VideoPlayer::getCurrentPlayTime()
{
    return _videoOnly ? _videoTimer.getCurrentTime() : _audioDecoder.getCurrentTime();
}

VIDEO_PLAYER_STATUS VideoPlayer::getCurrentStatue()
{
    return _playerStatus;
}

void VideoPlayer::draw(AAPLEAGLLayer *_gllayer)
{
    dispatch_sync(_videoDecoder.bufferDispatchQueue, ^{
        if (_videoDecoder.currentImageBuffer)
            [_gllayer displayPixelBuffer:_videoDecoder.currentImageBuffer width:1280 height:720];
    });
}
