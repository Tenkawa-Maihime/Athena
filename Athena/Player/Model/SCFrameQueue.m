//
//  SCFrameQueue.m
//  Athena
//
//  Created by Theresa on 2018/12/28.
//  Copyright © 2018 Theresa. All rights reserved.
//

#import "SCFrameQueue.h"
#import "SCNV12VideoFrame.h"

@interface SCFrameQueue ()

@property (nonatomic, assign) BOOL isBlock;
@property (nonatomic, assign, readwrite) NSInteger count;
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, strong) NSMutableArray <SCFrame *> *frames;

@end

@implementation SCFrameQueue

- (void)dealloc {
    NSLog(@"Frame Queue dealloc");
}

- (instancetype)init {
    if (self = [super init]) {
        self.frames = [NSMutableArray array];
        self.condition = [[NSCondition alloc] init];
    }
    return self;
}

- (void)enqueueArray:(NSArray<SCFrame *> *)array {
    [self.condition lock];
    if (array.count == 0 || self.isBlock) {
        [self.condition unlock];
        return;
    }
    [self.frames addObjectsFromArray:array];
    self.count += array.count;
    [self.condition unlock];
}

- (void)enqueueAndSort:(SCFrame *)frame {
    BOOL added = NO;
    if (self.frames.count > 0) {
        for (int i = (int)self.frames.count - 1; i >= 0; i--) {
            SCFrame *obj = [self.frames objectAtIndex:i];
            if (frame.position > obj.position) {
                [self.frames insertObject:frame atIndex:i + 1];
                added = YES;
                break;
            }
        }
    }
    if (!added) {
        [self.frames addObject:frame];
    }
    self.count++;
}

- (void)enqueueArrayAndSort:(NSArray<SCFrame *> *)array {
    [self.condition lock];
    if (array.count == 0 || self.isBlock) {
        [self.condition unlock];
        return;
    }
    for (SCFrame *frame in array) {
        [self enqueueAndSort:frame];
    }
    [self.condition unlock];
}

- (SCFrame *)dequeueFrame {
    [self.condition lock];
    SCFrame *frame;
    if (self.frames.count <= 0) {
        [self.condition unlock];
        return frame;
    }
    frame = self.frames.firstObject;
    [self.frames removeObjectAtIndex:0];
    self.count--;
    [self.condition unlock];
    return frame;
}

- (void)flushAndBlock {
    [self.condition lock];
    [self.frames removeAllObjects];
    self.count = 0;
    self.isBlock = YES;
    [self.condition unlock];
}
- (void)unblock {
    [self.condition lock];
    self.isBlock = NO;
    [self.condition unlock];
}

@end
