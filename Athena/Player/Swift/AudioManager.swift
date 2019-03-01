//
//  AudioManager.swift
//  Athena
//
//  Created by Theresa on 2019/2/6.
//  Copyright © 2019 Theresa. All rights reserved.
//

import Foundation
import AVFoundation
import Accelerate

@objc protocol AudioManagerDelegate: NSObjectProtocol {
    func fetch(outputData: UnsafeMutablePointer<Float>, numberOfFrames: UInt32, numberOfChannels: UInt32)
}

@objc class AudioManager: NSObject {
    @objc weak var delegate: AudioManagerDelegate?
    var outData = UnsafeMutablePointer<Float>.allocate(capacity: 4096 * 2)
    
    var audioUnit: AudioUnit!
    let audioSession = AVAudioSession.sharedInstance()
    
    var callback: AURenderCallback = {(
        inRefCon: UnsafeMutableRawPointer,
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames:UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus in
        
        if let ioData = ioData {
            for iBuffer in 0..<ioData.pointee.mNumberBuffers {
                memset(ioData[Int(iBuffer)].mBuffers.mData, 0, Int(ioData[Int(iBuffer)].mBuffers.mDataByteSize))
            }
            let player = Unmanaged<AudioManager>.fromOpaque(inRefCon).takeUnretainedValue()
            if let delegate = player.delegate {
                delegate.fetch(outputData: player.outData, numberOfFrames: inNumberFrames, numberOfChannels: 2)
                var scale = Float(INT16_MAX)
                vDSP_vsmul(player.outData, 1, &scale, player.outData, 1, vDSP_Length(inNumberFrames * 2));
                for iBuffer in 0..<ioData.pointee.mNumberBuffers {
                    let thisNumChannels = ioData[Int(iBuffer)].mBuffers.mNumberChannels
                    for iChannel in 0..<thisNumChannels {
                        vDSP_vfix16(player.outData + Int(iChannel),
                                    2,
                                    ioData[Int(iBuffer)].mBuffers.mData!.assumingMemoryBound(to: Int16.self) + Int(iChannel),
                                    vDSP_Stride(thisNumChannels),
                                    vDSP_Length(inNumberFrames))
                    }
                }
                return noErr
            }
            
        }
        
        return noErr
    }
    
    @objc public override init() {
        do {
            try audioSession.setPreferredSampleRate(44_100)
            // https://stackoverflow.com/questions/51010390/avaudiosession-setcategory-swift-4-2-ios-12-play-sound-on-silent
            if #available(iOS 10.0, *) {
                try audioSession.setCategory(.playback, mode: .default, options: [])
            } else {
                audioSession.perform(NSSelectorFromString("setCategory:withOptions:error:"), with: AVAudioSession.Category.playAndRecord, with:  [AVAudioSession.CategoryOptions.defaultToSpeaker])
            }
            try audioSession.setActive(true)
        } catch {
            print("error")
        }
        super.init()
        initPlayer()
    }
    
    func initPlayer() {
        var audioDesc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                  componentSubType: kAudioUnitSubType_RemoteIO,
                                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                                  componentFlags: 0,
                                                  componentFlagsMask: 0)
        guard let inputComponent = AudioComponentFindNext(nil, &audioDesc) else { return }
        AudioComponentInstanceNew(inputComponent, &audioUnit)
        
        var outputFormat = AudioStreamBasicDescription(mSampleRate: 44100,
                                                       mFormatID: kAudioFormatLinearPCM,
                                                       mFormatFlags: kLinearPCMFormatFlagIsSignedInteger,
                                                       mBytesPerPacket: 4,
                                                       mFramesPerPacket: 1,
                                                       mBytesPerFrame: 4,
                                                       mChannelsPerFrame: 2,
                                                       mBitsPerChannel: 16,
                                                       mReserved: 0)
        var result = AudioUnitSetProperty(audioUnit,
                                          kAudioUnitProperty_StreamFormat,
                                          kAudioUnitScope_Input,
                                          0,
                                          &outputFormat,
                                          UInt32(MemoryLayout.size(ofValue: outputFormat)))
        print(result)
        var callbackStruct = AURenderCallbackStruct()
        callbackStruct.inputProc = callback
        callbackStruct.inputProcRefCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        result = AudioUnitSetProperty(audioUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input,
                                      0,
                                      &callbackStruct,
                                      UInt32(MemoryLayout<AURenderCallbackStruct>.size));
        print(result)
        result = AudioUnitInitialize(audioUnit)
        print(result)
    }
    
    @objc func play() {
        AudioOutputUnitStart(audioUnit)
    }

    @objc func stop() {
        AudioOutputUnitStop(audioUnit)
    }
}