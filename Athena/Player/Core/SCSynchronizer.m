//
//  SCSynchronizer.m
//  Athena
//
//  Created by Theresa on 2019/01/30.
//  Copyright © 2019 Theresa. All rights reserved.
//

#import "SCSynchronizer.h"
#import "SCAudioFrame.h"

@interface SCSynchronizer ()

@property (nonatomic, assign) NSTimeInterval audioFramePlayTime;
@property (nonatomic, assign) NSTimeInterval audioFramePosition;

@end

@implementation SCSynchronizer

- (void)updateAudioClock:(NSTimeInterval)position {
    @synchronized (self) {
        self.audioFramePlayTime = [NSDate date].timeIntervalSince1970;
        self.audioFramePosition = position;
    }
}

- (BOOL)shouldRenderVideoFrame:(NSTimeInterval)position duration:(NSTimeInterval)duration {
    @synchronized (self) {
        NSTimeInterval time = [NSDate date].timeIntervalSince1970;
        BOOL result = self.audioFramePosition + time - self.audioFramePlayTime >= position + duration;
        return result;
    }
}


@end
