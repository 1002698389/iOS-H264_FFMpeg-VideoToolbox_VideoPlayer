//
//  VideoTimer.cpp
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 1/11/16.
//  Copyright © 2016 Cong Ku. All rights reserved.
//

#ifndef VideoTimer_hpp
#define VideoTimer_hpp

#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>

class VideoTimer {
private:
    
    float _rate;
    
    double _world_start_time;
    double _additional_time;
    
    double _current_time_collapsed;
    
    bool _paused;
    
public:
    
    VideoTimer()
    {
        _paused = true;
        _rate = 1.0f;
    }
    
    void setRate(float rate)
    {
        _rate = rate;
    }
    
    void setCurrentTime(float time)
    {
        _additional_time = time;
        _world_start_time = CFAbsoluteTimeGetCurrent();
        _current_time_collapsed = 0;
    }
    
    float getCurrentTime()
    {
        if (!_paused)
        {
            double absTime = CFAbsoluteTimeGetCurrent();
            _current_time_collapsed = (absTime - _world_start_time) * _rate + _additional_time;
        }
        return ((int)(_current_time_collapsed * 1000) / 1000.0); //cut down timer percision
    }
    
    void start(float time)
    {
        setCurrentTime(time);
        _paused = false;
    }
    
    void pause()
    {
        _current_time_collapsed = (CFAbsoluteTimeGetCurrent() - _world_start_time) * _rate + _additional_time;
        _paused = true;
    }
    
    void resume()
    {
        _additional_time = _current_time_collapsed;
        _world_start_time = CFAbsoluteTimeGetCurrent();
        _current_time_collapsed = 0;
        _paused = false;
    }
};

#endif