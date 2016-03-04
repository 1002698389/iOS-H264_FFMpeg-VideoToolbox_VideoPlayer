//
//  ViewController.m
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 12/2/15.
//  Copyright © 2015 Cong Ku. All rights reserved.
//

#import "ViewController.h"
#import "AAPLEAGLLayer.h"


@interface ViewController ()
{
    AAPLEAGLLayer *_glLayer;
}

@property CADisplayLink *displayLink;

-(void)appDidEnterBackground;
-(void)appWillEnterForeground;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    NSString* videoPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"page18-movie-0.m4v"];
    [self loadVideo:videoPath withAudio:NULL];
}

- (IBAction)Pause_Resume:(id)sender
{
//    switch (_player.getCurrentStatue()) {
//        case VIDEO_PLAYER_READY:
//        {
//            [self start];
//        }
//            break;
//            
//        case VIDEO_PLAYER_PLAYING:
//        {
//            [self pause];
//        }
//            break;
//        
//        case VIDEO_PLAYER_PAUSED:
//        {
//            [self resume];
//        }
//            break;
//        default:
//            break;
//    }
    if (_playerIOS.playerStatus == PZVIDEOSOURCE_STATE_READYTOPLAY) {
        if (!_playerIOS.playerStarted || !_playerIOS.playback)
            [self start];
        else
        {
           if (_playerIOS.playerStarted)
           {
               NSLog(@"called pause");
               [self pause];
           }
        }
    }
}

- (IBAction)Next_20_Secs:(id)sender
{
    float newTime = [_playerIOS getCurrentPlayTime] + 20;
    [self seek:newTime];
}

- (IBAction)Prev_20_Secs:(id)sender
{
    float newTime = [_playerIOS getCurrentPlayTime] - 20;
    newTime = newTime < 0 ? 0 : newTime;
    [self seek:newTime];
}

- (IBAction)SeekToTime:(id)sender
{
    [self seek:241];
}

- (int)loadVideo:(NSString*)videoPath withAudio:(NSString*)audioPath
{
    char* v_path = (char*)[videoPath cStringUsingEncoding:NSASCIIStringEncoding];
    std::string v_path_string("https://s3-us-west-1.amazonaws.com/plumzi-streaming-tests/pz_disney_poc/disney_poc_matrix_baseline_crf26.m4v");
    char* a_path = audioPath == NULL ? NULL : (char*)[audioPath cStringUsingEncoding:NSASCIIStringEncoding];
    //_player.init((char*)v_path, a_path);
    _playerIOS = [[VideoPlayerIOS alloc] init];
    [_playerIOS load:videoPath];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback)];
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.displayLink setPaused:false];
    
    return 0;
}

-(void)start
{
    //_player.start();
    [_playerIOS play:1.0];
}

-(void)pause
{
    //_player.pause();
    [_playerIOS pause];
}

-(void)resume
{
    //_player.resume();
    [_playerIOS play:1.0];
}

-(void)seek:(float)time
{
    //_player.seek(time);
    [_playerIOS seekTo:time];
}

-(void)appWillEnterForeground
{
   
}

-(void)appDidEnterBackground
{
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void)displayLinkCallback
{
    if (!_glLayer)
    {
        _glLayer = [[AAPLEAGLLayer alloc] initWithFrame:self.view.bounds];
        [self.view.layer insertSublayer:_glLayer atIndex:0];
    }
    
    //_player.draw(_glLayer);
    [_playerIOS draw:_glLayer];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
