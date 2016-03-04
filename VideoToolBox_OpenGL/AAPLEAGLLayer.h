/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  This CAEAGLLayer subclass demonstrates how to draw a CVPixelBufferRef using OpenGLES and display the timecode associated with that pixel buffer in the top right corner.
  
 */

//@import QuartzCore;


#include <QuartzCore/QuartzCore.h>
#include <CoreVideo/CoreVideo.h>
#import <GLKit/GLKit.h>

@interface AAPLEAGLLayer : CAEAGLLayer
{
    GLuint mVertexBuffer;
    uint8_t trueBuffer[1280 * 720 * 3];
}
@property CVPixelBufferRef pixelBuffer;
- (id)initWithFrame:(CGRect)frame;
- (void)resetRenderBuffer;

- (void)displayRGBBuffer:(uint8_t*)buffer;
- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer width:(uint32_t)frameWidth height:(uint32_t)frameHeight;

@end
