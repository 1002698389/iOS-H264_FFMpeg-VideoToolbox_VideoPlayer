//
//  ViewController.h
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 12/2/15.
//  Copyright © 2015 Cong Ku. All rights reserved.
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
#include "VideoPlayerIOS.h"

@interface ViewController : UIViewController
{
    VideoPlayer _player;
    VideoPlayerIOS* _playerIOS;
}
@property (weak, nonatomic) IBOutlet UIButton *Paly_Pause_Button;
- (IBAction)Pause_Resume:(id)sender;
- (IBAction)Next_20_Secs:(id)sender;
- (IBAction)Prev_20_Secs:(id)sender;
- (IBAction)SeekToTime:(id)sender;

-(void)start;
-(void)pause;
-(void)resume;



@end

