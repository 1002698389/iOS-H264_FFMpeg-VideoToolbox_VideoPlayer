//
//  ViewController.h
//  VideoToolBox_OpenGL_TVOS
//
//  Created by Cong Ku on 1/25/16.
//  Copyright © 2016 Cong Ku. All rights reserved.
//

#include <string>
#include <sstream>
#include <iostream>

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

#include "VideoPlayer.hpp"


@interface ViewController : UIViewController
{
    VideoPlayer _player;
}

- (IBAction)Pause_Resume_tvos:(id)sender;
- (IBAction)Next_20_Secs_tvos:(id)sender;
- (IBAction)Prev_20_Secs_tvos:(id)sender;
- (IBAction)SeekToTime_tvos:(id)sender;

-(void)start;
-(void)pause;
-(void)resume;

@end

