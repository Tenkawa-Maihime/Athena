//
//  Controller.swift
//  Athena
//
//  Created by Theresa on 2019/2/6.
//  Copyright © 2019 Theresa. All rights reserved.
//

import Foundation
import MetalKit

enum ControlState: Int {
    case Origin = 0
    case Opened
    case Playing
    case Paused
    case Closed
}

@objc class Controller: NSObject {
    
    private let context: SCFormatContext
    
    private var vtDecoder: VTDecoder?
    private var ffDecoder: FFDecoder?
    private var videoDecoder: VideoDecoder?
    private var audioDecoder: SCAudioDecoder?
    
    private let videoFrameQueue: FrameQueue
    private let audioFrameQueue: SCFrameQueue
    private let videoPacketQueue: SCPacketQueue
    private let audioPacketQueue: SCPacketQueue
    
    private let readPacketOperation: BlockOperation
    private let videoDecodeOperation: BlockOperation
    private let audioDecodeOperation: BlockOperation
    private let controlQueue: OperationQueue
    
    private weak var mtkView: MTKView?
    private let render: Render
    
    public private(set) var state: ControlState = .Origin
    
    private var isSeeking: Bool
    private var videoSeekingTime: TimeInterval
    private var videoFrame: Frame?
    
    deinit {
        
    }
    
    @objc init(renderView: MTKView) {
        
        videoPacketQueue = SCPacketQueue()
        audioPacketQueue = SCPacketQueue()
        videoFrameQueue = FrameQueue()
        audioFrameQueue = SCFrameQueue()
        
        readPacketOperation = BlockOperation()
        videoDecodeOperation = BlockOperation()
        audioDecodeOperation = BlockOperation()
        controlQueue = OperationQueue()
        
        context = SCFormatContext()
        render = Render()
        isSeeking = false
        videoSeekingTime = 0
        
        mtkView = renderView
        mtkView!.device = render.device
        mtkView!.depthStencilPixelFormat = .invalid
        mtkView!.framebufferOnly = false
        mtkView!.colorPixelFormat = .bgra8Unorm

        super.init()
        mtkView!.delegate = self
    }
    
    @objc func open(path: NSString) {
        context.openPath(String(path))
        vtDecoder = VTDecoder(formatContext: context)
        videoDecoder = vtDecoder
        start()
    }
    
    func start() {
        readPacketOperation.addExecutionBlock {
            self.readPacket()
        }
        videoDecodeOperation.addExecutionBlock {
            self.decodeVideoFrame()
        }
        audioDecodeOperation.addExecutionBlock {
            
        }
        controlQueue.addOperation(readPacketOperation)
        controlQueue.addOperation(videoDecodeOperation)
        controlQueue.addOperation(audioDecodeOperation)
    }
    
    func pause() {
        
    }
    
    func resume() {
        
    }
    
    func close() {
        state = .Closed
        controlQueue.cancelAllOperations()
        controlQueue.waitUntilAllOperationsAreFinished()
        flushQueue()
        context.closeFile()
    }
    
    func seeking(time: TimeInterval) {
        
    }
    
    func appWillResignActive() {
        pause()
    }
    
    func flushQueue() {
        videoFrameQueue.flush()
        audioFrameQueue.flush()
        videoPacketQueue.flush()
        audioPacketQueue.flush()
    }
    
    func readPacket() {
        var finished = false
        while !finished {
            if state == .Closed {
                break
            }
            if state == .Paused {
                Thread.sleep(forTimeInterval: 0.03)
                continue
            }
            if videoPacketQueue.packetTotalSize + audioPacketQueue.packetTotalSize > 10 * 1024 * 1024 {
                Thread.sleep(forTimeInterval: 0.03)
                continue
            }
            if isSeeking {
                context.seekingTime(videoSeekingTime)
                flushQueue()
                videoPacketQueue.enqueueDiscardPacket()
                audioPacketQueue.enqueueDiscardPacket()
                isSeeking = false
                continue
            }
            let packet: UnsafeMutablePointer<AVPacket> = av_packet_alloc()
            let result = context.readFrame(packet)
            if result < 0 {
                finished = true
                break
            } else {
                if packet.pointee.stream_index == context.videoIndex {
                    videoPacketQueue.enqueue(packet.pointee)
                } else if packet.pointee.stream_index == context.audioIndex {
                    audioPacketQueue.enqueue(packet.pointee)
                }
            }
        }
    }
    
    func decodeVideoFrame() {
        while state != .Closed {
            if state == .Paused {
                Thread.sleep(forTimeInterval: 0.03)
                continue
            }
            if videoFrameQueue.count > 10 {
                Thread.sleep(forTimeInterval: 0.03)
                continue
            }
            var packet = videoPacketQueue.dequeuePacket()
            if packet.flags == AV_PKT_FLAG_DISCARD {
                avcodec_flush_buffers(context.videoCodecContext)
                videoFrameQueue.flush()
                videoFrameQueue.enqueueAndSort(frames: NSArray.init(object: MarkerFrame.init()))
                av_packet_unref(&packet);
                continue;
            }
            if packet.data != nil && packet.stream_index >= 0 {
                let frames = videoDecoder!.decode(packet: packet)
                videoFrameQueue.enqueueAndSort(frames: frames)
            }
        }
    }
    
    func rendering() {
        if let playFrame = videoFrame {
            if playFrame.isMember(of: MarkerFrame.self) {
                videoSeekingTime = -1
                videoFrame = nil
                return
            }
            if videoSeekingTime > 0 {
                videoFrame = nil
                return
            }
            render.render(frame: playFrame as! RenderData, drawIn: mtkView!)
            videoFrame = nil
        } else {
            videoFrame = videoFrameQueue.dequeue()
            if videoFrame == nil {
                return
            }
        }
    }
}

extension Controller: MTKViewDelegate {
    func draw(in view: MTKView) {
        rendering()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
