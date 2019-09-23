//
//  AudioInputMapper.h
//  AudioKitSampleRate
//
//  Created by Martin Mlostek on 23.09.19.
//  Copyright © 2019 nomad5. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The main instance that handles audio input and passes it to Mirga
@interface AudioInputMapper : NSObject

    /// Setup down audio input
    - (void)setup;

    /// Stop audio input
    - (void)tearDown;

    /// Start audio input
    - (void)start;

    /// Stop audio input
    - (void)stop;

    /// Indicator if the audio chain is being modified
    @property(nonatomic, assign, readonly) BOOL audioChainIsBeingReconstructed;

@end


NS_ASSUME_NONNULL_END
