//
//  SCControl.m
//  Athena
//
//  Created by Theresa on 2018/12/29.
//  Copyright © 2018 Theresa. All rights reserved.
//

#import <libavformat/avformat.h>
#import "SCFormatContext.h"
#import "SCAudioManager.h"
#import "SCControl.h"

#import "SCSynchronizer.h"
#import "SCFrame.h"
#import "SCAudioFrame.h"

#import "SCAudioDecoder.h"
#import "SCVTDecoder.h"
#import "SCVideoDecoder.h"
#import "SCDecoderInterface.h"
#import "SCFrameQueue.h"
#import "SCPacketQueue.h"
#import "SCRender.h"

#import "SCDemuxLayer.h"
#import "SCRenderLayer.h"
#import "SCDecoderLayer.h"

@interface SCControl () 

@property (nonatomic, strong) SCFormatContext *context;

@property (nonatomic, strong) SCVTDecoder *VTDecoder;
@property (nonatomic, strong) SCVideoDecoder *videoDecoder;
@property (nonatomic, strong) id<SCDecoderInterface> currentDecoder;
@property (nonatomic, strong) SCAudioDecoder *audioDecoder;

@property (nonatomic, strong) SCFrameQueue *videoFrameQueue;
@property (nonatomic, strong) SCFrameQueue *audioFrameQueue;

@property (nonatomic, strong) NSInvocationOperation *videoDecodeOperation;
@property (nonatomic, strong) NSInvocationOperation *audioDecodeOperation;
@property (nonatomic, strong) NSOperationQueue *controlQueue;

@property (nonatomic, weak  ) MTKView *mtkView;

@property (nonatomic, assign, readwrite) SCControlState controlState;

//synchronize
@property (nonatomic, assign) BOOL isSeeking;
@property (nonatomic, assign) NSTimeInterval videoSeekingTime;
@property (nonatomic, assign) NSTimeInterval audioSeekingTime;

@property (nonatomic, strong) SCDemuxLayer *demuxLayer;
@property (nonatomic, strong) SCRenderLayer *renderLayer;
@property (nonatomic, strong) SCDecoderLayer *decoderLayer;

@end

@implementation SCControl

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
}

- (instancetype)initWithRenderView:(MTKView *)view {
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
        _videoFrameQueue  = [[SCFrameQueue alloc] init];
        _audioFrameQueue  = [[SCFrameQueue alloc] init];
        _videoSeekingTime = -DBL_MAX;
        _audioSeekingTime = -DBL_MAX;
        _mtkView = view;
    }
    return self;
}

- (void)appWillResignActive {
    [self pause];
}

- (void)openPath:(NSString *)filename {
    _context = [[SCFormatContext alloc] init];
    [_context openPath:filename];
    
    _VTDecoder    = [[SCVTDecoder alloc] initWithFormatContext:_context];
    _videoDecoder = [[SCVideoDecoder alloc] initWithFormatContext:_context];
    _audioDecoder = [[SCAudioDecoder alloc] initWithFormatContext:_context];
    _currentDecoder = _videoDecoder;
    
    self.demuxLayer = [[SCDemuxLayer alloc] initWithContext:self.context];
    self.renderLayer = [[SCRenderLayer alloc] initWithContext:self.context renderView:self.mtkView video:self.videoFrameQueue audio:self.audioFrameQueue];
    self.decoderLayer = [[SCDecoderLayer alloc] initWithContext:self.context
                                                     demuxLayer:self.demuxLayer
                                                          video:self.videoFrameQueue
                                                          audio:self.audioFrameQueue];
    [self start];
}

- (void)start {
    [self.demuxLayer start];
    [self.renderLayer start];
    [self.decoderLayer start];
    
    self.controlQueue = [[NSOperationQueue alloc] init];
    self.controlQueue.qualityOfService = NSQualityOfServiceUserInteractive;
    [self.controlQueue addOperation:self.videoDecodeOperation];
    [self.controlQueue addOperation:self.audioDecodeOperation];
    
    self.controlState = SCControlStatePlaying;
}

- (void)pause {
    [self.demuxLayer pause];
    [self.decoderLayer pause];
    [self.renderLayer pause];
    self.controlState = SCControlStatePaused;
}

- (void)resume {
    [self.demuxLayer resume];
    [self.decoderLayer resume];
    [self.renderLayer resume];
    self.controlState = SCControlStatePlaying;
}

- (void)close {
    [self.demuxLayer close];
    [self.decoderLayer close];
    [self.renderLayer close];
    self.controlState = SCControlStateClosed;
    [self.controlQueue cancelAllOperations];
    [self.controlQueue waitUntilAllOperationsAreFinished];
    self.videoDecodeOperation = nil;
    self.audioDecodeOperation = nil;
    [self.context closeFile];
}

- (void)seekingTime:(NSTimeInterval)percentage {
    self.videoSeekingTime = percentage * self.context.duration;
    self.audioSeekingTime = self.videoSeekingTime;
    self.isSeeking = YES;
}

@end