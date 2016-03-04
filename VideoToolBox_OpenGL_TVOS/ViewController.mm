//
//  ViewController.m
//  VideoToolBox_OpenGL_TVOS
//
//  Created by Cong Ku on 1/25/16.
//  Copyright © 2016 Cong Ku. All rights reserved.
//

#import "ViewController.h"

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
    
    //NSString* videoPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"disney_poc_baseline_crf26.m4v"];
    NSString* videoPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"video10_base.m4v"];
    
    NSString* audioPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"cb_122_24.m4a"];
    [self loadVideo:videoPath withAudio:NULL];
}

- (IBAction)Pause_Resume_tvos:(id)sender
{
    switch (_player.getCurrentStatue()) {
        case VIDEO_PLAYER_READY:
        {
            [self start];
        }
            break;
            
        case VIDEO_PLAYER_PLAYING:
        {
            [self pause];
        }
            break;
            
        case VIDEO_PLAYER_PAUSED:
        {
            [self resume];
        }
            break;
        default:
            break;
    }
}

- (IBAction)Next_20_Secs_tvos:(id)sender
{
    float newTime = _player.getCurrentPlayTime() + 20;
    [self seek:newTime];
}

- (IBAction)Prev_20_Secs_tvos:(id)sender
{
    float newTime = _player.getCurrentPlayTime() - 20;
    newTime = newTime < 0 ? 0 : newTime;
    [self seek:newTime];
}

- (IBAction)SeekToTime_tvos:(id)sender
{
    [self seek:3];
}

- (int)loadVideo:(NSString*)videoPath withAudio:(NSString*)audioPath
{
    char* v_path = (char*)[videoPath cStringUsingEncoding:NSASCIIStringEncoding];
    std::string v_path_string("https://s3-us-west-1.amazonaws.com/plumzi-streaming-tests/pz_disney_poc/disney_poc_matrix_baseline_crf26.m4v");
    char* a_path = audioPath == NULL ? NULL : (char*)[audioPath cStringUsingEncoding:NSASCIIStringEncoding];
    _player.init((char*)v_path, a_path);
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback)];
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.displayLink setPaused:false];
    
    return 0;
}


-(void)start
{
    _player.start();
}

-(void)pause
{
    _player.pause();
}

-(void)resume
{
    _player.resume();
}

-(void)seek:(float)time
{
    _player.seek(time);
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
    
    _player.draw(_glLayer);
}

-(void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
