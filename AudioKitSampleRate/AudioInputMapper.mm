//
//  AudioInputMapper.m
//  AudioKitSampleRate
//
//  Created by Martin Mlostek on 23.09.19.
//  Copyright © 2019 nomad5. All rights reserved.
//

#import <iostream>
#import "AudioInputMapper.h"

#define kOutputBus  0
#define kInputBus   1

/// Generic logging
#define Log(...)      NSLog(@"%@", [NSString stringWithFormat:__VA_ARGS__]);
/// Error logging
#define LogError(...) NSLog(@"%@", [NSString stringWithFormat:__VA_ARGS__]);

/// Remove newline chars
#define TrimNewLine(string) [[string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "]

/// Helper to verify audio session setup results
#define VerifyError(execution, message) { \
OSStatus _result = execution; \
if(_result) { \
NSLog(@"AudioInputMapper Error: %i / %@", (int)_result, [NSString stringWithUTF8String:message]); \
return; \
} }

/*********************************************************************************************************
 * Structure for the audio callback
 * Maybe it's better to use the inRefCon to point to the audio mapper?
 */
struct CallbackData
{
    AudioBufferList audioBufferList;
    AudioUnit       audioUnit;
    BOOL            *audioChainIsBeingReconstructed;

    CallbackData() : audioChainIsBeingReconstructed(NULL) {}
} callbackData;

/*********************************************************************************************************
 * The audio input callback
 */
static OSStatus audioInputCallback(void __unused *inRefCon,
                                   AudioUnitRenderActionFlags *ioActionFlags,
                                   const AudioTimeStamp *inTimeStamp,
                                   UInt32  __unused inBusNumber,
                                   UInt32 inNumberFrames,
                                   AudioBufferList __unused *ioData)
{
    OSStatus err = noErr;
    if(!*callbackData.audioChainIsBeingReconstructed)
    {
        // we are calling AudioUnitRender on the input bus of AURemoteIO
        // this will store the audio data captured by the microphone in cd.audioBufferList
        err = AudioUnitRender(callbackData.audioUnit, ioActionFlags, inTimeStamp, kInputBus, inNumberFrames, &callbackData.audioBufferList);
        // check if the sample count is set correctly
        if(callbackData.audioBufferList.mBuffers[0].mDataByteSize != inNumberFrames * sizeof(float))
        {
            std::cerr << "!!! Buffer size mismatch: mDataByteSize: " << callbackData.audioBufferList.mBuffers[0].mDataByteSize << " != inNumberFrames: " << inNumberFrames * sizeof(float) << std::endl;
        }
        // Assert that we only received one buffer
        assert(callbackData.audioBufferList.mNumberBuffers == 1);
    }
    return err;
}

/*********************************************************************************************************
 * The audio output callback
 */
static OSStatus audioOutputCallback(void *inRefCon,
                                    AudioUnitRenderActionFlags *ioActionFlags,
                                    const AudioTimeStamp *inTimeStamp,
                                    UInt32 inBusNumber,
                                    UInt32 inNumberFrames,
                                    AudioBufferList *ioData)
{
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
    return noErr;
}

/*********************************************************************************************************
 * Main instance to setup audio input processing
 */
@implementation AudioInputMapper
    {
        AudioUnit audioUnit;
        uint32_t  blockSize;
        uint32_t  sampleRate;
        bool      lastVoiceProcessingConfig;
    }

    /// Construction with dependencies resolved by factory
    - (_Nonnull instancetype)init
    {
        self = [super init];
        if(self)
        {
            blockSize  = 1024;
            sampleRate = AVAudioSession.sharedInstance.sampleRate;
        }
        return self;
    }

#pragma mark - Starting

    /// Setup audio chain
    - (void)setup:(bool)voiceProcessingEnabled
    {
        lastVoiceProcessingConfig = voiceProcessingEnabled;
        // TODO check if this is fixing all issues, if so, remove the code, if not, run
        [self setupAudioSession];
        [self setupIOUnit];
    }

    /// Setup the audio session
    - (void)setupAudioSession
    {
        // Configure the audio session
        AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];

        // we are going to play and record so we pick that category
        NSError *error = nil;
        [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
        VerifyError((OSStatus) error.code, "couldn't set session's audio category");

        //        [sessionInstance overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
        //        VerifyError((OSStatus) error.code, "couldn't override output to speaker");
        //
        //        // set to measurement
        //        [sessionInstance setMode:AVAudioSessionModeMeasurement error:&error];
        //        VerifyError((OSStatus) error.code, "couldn't set session's audio mode");

        // set the buffer duration
        NSTimeInterval bufferDuration = (double) blockSize / (double) sampleRate;
        [sessionInstance setPreferredIOBufferDuration:bufferDuration error:&error];
        VerifyError((OSStatus) error.code, "couldn't set session's I/O buffer duration");

        // set the session's sample rate
        [sessionInstance setPreferredSampleRate:sampleRate error:&error];
        VerifyError((OSStatus) error.code, "couldn't set session's preferred sample rate");

        // add interruption handler
        [[NSNotificationCenter defaultCenter] addObserver:self
                               selector:@selector(handleInterruption:)
                               name:AVAudioSessionInterruptionNotification
                               object:sessionInstance];

        // we don't do anything special in the route change notification
        [[NSNotificationCenter defaultCenter] addObserver:self
                               selector:@selector(handleRouteChange:)
                               name:AVAudioSessionRouteChangeNotification
                               object:sessionInstance];

        // if media services are reset, we need to rebuild our audio chain
        [[NSNotificationCenter defaultCenter] addObserver:self
                               selector:@selector(handleMediaServerReset:)
                               name:AVAudioSessionMediaServicesWereResetNotification
                               object:sessionInstance];

        // activate the audio session
        [[AVAudioSession sharedInstance] setActive:YES error:&error];
        VerifyError((OSStatus) error.code, "couldn't set session active");

        //        // override to speaker
        //        UInt32 audioRouteOverride = kAudioSessionOverrideAudioRoute_Speaker;
        //        VerifyError(AudioSessionSetProperty(kAudioSessionProperty_OverrideAudioRoute,
        //                                            sizeof(audioRouteOverride),
        //                                            &audioRouteOverride),
        //                    "couldn't override route to speaker");
    }

    /// Setup the audio input and output
    - (void)setupIOUnit
    {
        // Create a new instance of AURemoteIO
        AudioComponentDescription desc;
        desc.componentType         = kAudioUnitType_Output;
        desc.componentSubType      = lastVoiceProcessingConfig ? kAudioUnitSubType_VoiceProcessingIO : kAudioUnitSubType_RemoteIO;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        desc.componentFlags        = 0;
        desc.componentFlagsMask    = 0;

        AudioComponent comp = AudioComponentFindNext(NULL, &desc);
        VerifyError(AudioComponentInstanceNew(comp,
                                              &audioUnit),
                    "couldn't create a new instance of AURemoteIO");

        //  Enable input and output on AURemoteIO
        //  Input is enabled on the input scope of the input element
        //  Output is enabled on the output scope of the output element
        UInt32 on  = TRUE;
        UInt32 off = FALSE;
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Input,
                                         kInputBus,
                                         &on,
                                         sizeof(on)),
                    "could not enable input on AURemoteIO");
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Output,
                                         kOutputBus,
                                         &off,
                                         sizeof(off)),
                    "could not enable output on AURemoteIO");

        // Explicitly float as sample format
        AudioStreamBasicDescription ioFormat;
        ioFormat.mSampleRate       = sampleRate;
        ioFormat.mFormatID         = kAudioFormatLinearPCM;
        ioFormat.mFormatFlags      = kCAFLinearPCMFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
        ioFormat.mFramesPerPacket  = 1;
        ioFormat.mChannelsPerFrame = 1;
        ioFormat.mBitsPerChannel   = sizeof(float) * 8;
        ioFormat.mBytesPerFrame    = sizeof(float);
        ioFormat.mBytesPerPacket   = sizeof(float);
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Output,
                                         kInputBus,
                                         &ioFormat,
                                         sizeof(ioFormat)),
                    "couldn't set the input client format on AURemoteIO");
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Input,
                                         kOutputBus,
                                         &ioFormat,
                                         sizeof(ioFormat)),
                    "couldn't set the output client format on AudioUnit");

        //        VerifyError(AudioUnitSetProperty(audioUnit,
        //                                         kAUVoiceIOProperty_BypassVoiceProcessing,
        //                                         kAudioUnitScope_Global,
        //                                         kOutputBus,
        //                                         &off,
        //                                         sizeof(off)),
        //                    "couldn't disable voice processing on output");

        // Set the MaximumFramesPerSlice property. This property is used to describe to an audio unit the maximum number
        // of samples it will be asked to produce on any single given call to AudioUnitRender
        UInt32 maxFramesPerSlice = 4096;
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAudioUnitProperty_MaximumFramesPerSlice,
                                         kAudioUnitScope_Global,
                                         kOutputBus,
                                         &maxFramesPerSlice,
                                         sizeof(UInt32)),
                    "couldn't set max frames per slice on AURemoteIO");

        // Get the property value back from AURemoteIO. We are going to use this value to allocate buffers accordingly
        UInt32 propSize = sizeof(UInt32);
        VerifyError(AudioUnitGetProperty(audioUnit,
                                         kAudioUnitProperty_MaximumFramesPerSlice,
                                         kAudioUnitScope_Global,
                                         kOutputBus,
                                         &maxFramesPerSlice,
                                         &propSize),
                    "couldn't get max frames per slice on AURemoteIO");

        // We need references to certain data in the render callback
        // This simple struct is used to hold that information
        // Allocate buffer
        AudioBuffer buffer;
        buffer.mNumberChannels                      = 1;
        buffer.mDataByteSize                        = blockSize * sizeof(float);
        buffer.mData                                = malloc(buffer.mDataByteSize);
        callbackData.audioUnit                      = audioUnit;
        callbackData.audioChainIsBeingReconstructed = &_audioChainIsBeingReconstructed;
        callbackData.audioBufferList.mNumberBuffers = 1;
        callbackData.audioBufferList.mBuffers[0] = buffer;

        // Set the render callback on AURemoteIO
        AURenderCallbackStruct renderCallback;
        renderCallback.inputProc       = audioInputCallback;
        renderCallback.inputProcRefCon = NULL;
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAudioOutputUnitProperty_SetInputCallback,
                                         kAudioUnitScope_Global,
                                         kInputBus,
                                         &renderCallback,
                                         sizeof(renderCallback)),
                    "couldn't set render callback on AURemoteIO");

        //        // Set the output callback on AudioUnit
        //        renderCallback.inputProc       = audioOutputCallback;
        //        renderCallback.inputProcRefCon = NULL;
        //        VerifyError(AudioUnitSetProperty(audioUnit,
        //                                         kAudioUnitProperty_SetRenderCallback,
        //                                         kAudioUnitScope_Global,
        //                                         kOutputBus,
        //                                         &renderCallback,
        //                                         sizeof(renderCallback)),
        //                    "couldn't set render callback on AudioUnit");

        // Prevent buffer allocation (because we are passing our own buffer)
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAudioUnitProperty_ShouldAllocateBuffer,
                                         kAudioUnitScope_Output,
                                         kInputBus,
                                         &off,
                                         sizeof(off)),
                    "couldn't disable buffer allocation");

        // Enable automatic gain control for input
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAUVoiceIOProperty_VoiceProcessingEnableAGC,
                                         kAudioUnitScope_Global,
                                         kInputBus,
                                         &off,
                                         sizeof(off)),
                    "couldn't disable AGC for input");

        // Disable automatic gain control for output
        VerifyError(AudioUnitSetProperty(audioUnit,
                                         kAUVoiceIOProperty_VoiceProcessingEnableAGC,
                                         kAudioUnitScope_Global,
                                         kOutputBus,
                                         &off,
                                         sizeof(off)),
                    "couldn't disable AGC for output");

        // Initialize the AudioUnit instance
        OSStatus err = AudioUnitInitialize(audioUnit);
        if(err)
        {
            LogError(@"couldn't initialize AudioUnit instance");
        }
        else
        {
            Log(@"AudioUnit set up");
        }

    }

    /// Start the io unit
    - (void)start
    {
        OSStatus err = AudioOutputUnitStart(audioUnit);
        if(err)
        {
            LogError(@"couldn't start AURemoteIO: %d", (int) err);
        }
        else
        {
            Log(@"AudioUnit started");
        }
    }

#pragma mark - Stopping

    /// Stop the audio input
    - (void)stop
    {
        OSStatus err = AudioOutputUnitStop(audioUnit);
        if(err)
        {
            LogError(@"couldn't stop AURemoteIO: %d", (int) err);
        }
        else
        {
            Log(@"AudioUnit stopped");
        }
    }

    /// Tear down audio engine
    - (void)tearDown
    {
        OSStatus err = AudioUnitUninitialize(audioUnit);
        if(err)
        {
            LogError(@"couldn't un-initialize AudioUnit instance");
        }
        err = AudioComponentInstanceDispose(audioUnit);
        if(err)
        {
            LogError(@"couldn't dispose AudioUnit instance");
        }
        else
        {
            Log(@"AudioUnit teared down");
        }
    }

#pragma mark - Notification Callbacks

    /// Interruption callback
    - (void)handleInterruption:(NSNotification *)notification
    {
        UInt8 theInterruptionType = (UInt8) [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
        Log(@"Session interrupted > %s", theInterruptionType == AVAudioSessionInterruptionTypeBegan ? "Begin Interruption" : "End Interruption");

        if(theInterruptionType == AVAudioSessionInterruptionTypeBegan)
        {
            [self stop];
        }

        if(theInterruptionType == AVAudioSessionInterruptionTypeEnded)
        {
            // make sure to activate the session
            NSError *error = nil;
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            if(nil != error)
            {
                LogError(@"AVAudioSession set active failed with error: %@", error);
            }

            [self start];
        }
    }

    /// Route change callback
    - (void)handleRouteChange:(NSNotification *)notification
    {
        UInt8                          reasonValue       = (UInt8) [[notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey] intValue];
        AVAudioSessionRouteDescription *routeDescription = [notification.userInfo valueForKey:AVAudioSessionRouteChangePreviousRouteKey];
        switch(reasonValue)
        {
            case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
                Log(@"Route change: NewDeviceAvailable");
                break;
            case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
                Log(@"Route change: OldDeviceUnavailable");
                break;
            case AVAudioSessionRouteChangeReasonCategoryChange:
                Log(@"Route change: CategoryChange -> New Category: %@", TrimNewLine([AVAudioSession sharedInstance].category.description));
                break;
            case AVAudioSessionRouteChangeReasonOverride:
                Log(@"Route change: Override");
                break;
            case AVAudioSessionRouteChangeReasonWakeFromSleep:
                Log(@"Route change: WakeFromSleep");
                break;
            case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
                Log(@"Route change: NoSuitableRouteForCategory");
                break;
            case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
                Log(@"Route change: RouteConfigurationChange");
                break;
            case AVAudioSessionRouteChangeReasonUnknown:
                Log(@"Route change: ReasonUnknown");
                break;
            default:
                Log(@"Route change: Undefined");
        }

        Log(@"Previous route: %@", TrimNewLine(routeDescription.description));
        Log(@"Current route : %@", TrimNewLine([AVAudioSession sharedInstance].currentRoute.description));
        Log(@"-----------------------------------------------------------------------------")
    }

    /// Media server reset callback
    - (void)handleMediaServerReset:(NSNotification *)__unused notification
    {
        LogError(@"Media server has reset");
        _audioChainIsBeingReconstructed = YES;

        usleep(25000); //wait here for some time to ensure that we don't delete these objects while they are being accessed elsewhere

        [self setup: lastVoiceProcessingConfig];
        [self start];

        _audioChainIsBeingReconstructed = NO;
    }

@end
