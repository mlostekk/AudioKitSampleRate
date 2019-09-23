//
//  ViewController.swift
//  AudioKitSampleRate
//
//  Created by Martin Mlostek on 22.08.19.
//  Copyright © 2019 nomad5. All rights reserved.
//

import UIKit
import AVFoundation
import AudioKit

class ViewController: UIViewController {

    /// Ui stuff
    @IBOutlet weak var startEngineButton: UIButton!
    @IBOutlet weak var loadAndPlayButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!

    /// The main output mixer (after the amplitude tracker)
    private var masterMixer:  AKMixer?

    /// Instance of the AKPlayer
    private var audioPlayer: AudioKitPlayer? = nil

    /// Audio input mapper
    private let audioInputMapper: AudioInputMapper

    /// Default constructor, shall not pass
    required init?(coder aDecoder: NSCoder) {
        audioInputMapper = AudioInputMapper()
        super.init(coder: aDecoder)
    }


    /// Start audiokit
    @IBAction func onStartEngine(_ sender: Any) {
        startEngineButton.setEnabled(false)
        loadAndPlayButton.setEnabled(true)
        startEngine()
    }

    /// Start audio
    @IBAction func onLoadAndPlay(_ sender: Any) {
        loadAndPlayButton.setEnabled(false)
        // reset
        audioPlayer?.stop()
        audioPlayer = nil
        // restart
        let url = Bundle.main.url(forResource: "sound", withExtension: "wav")!
        audioPlayer = AudioKitPlayer(viewController: self, resourceUrl: url)
        audioPlayer?.schedulePlayback()
        stopButton.setEnabled(true)
    }

    /// Stop audio
    @IBAction func onStop(_ sender: Any) {
        stopButton.setEnabled(false)
        loadAndPlayButton.setEnabled(true)
        // reset
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// View loaded
    override func viewDidLoad() {
        super.viewDidLoad()
        // global settings
        AKAudioFile.cleanTempDirectory()
        AKSettings.defaultToSpeaker = true
        AKSettings.enableRouteChangeHandling = true
        AKSettings.enableCategoryChangeHandling = true
        AKSettings.audioInputEnabled = true
        AKSettings.playbackWhileMuted = false
        AKSettings.enableLogging = true
        // main mixer
        masterMixer = AKMixer()
    }

    /// Start engine
    func startEngine() {
        // connect main nodes
        AudioKit.output = masterMixer!
        // start
        do {
            try AKSettings.setSession(category: .playAndRecord, with: .defaultToSpeaker)
            try AudioKit.start()
            audioInputMapper.setup()
            audioInputMapper.start()
        } catch {
            fatalError("coult not start audiokit")
        }
    }

    /// Attach output
    func attach(audioPlayer: AKAudioPlayer) {
        audioPlayer >>> masterMixer!
    }
}


/// Audiokit implementation
class AudioKitPlayer {

    /// Instance of the AKPlayer
    // We only need to make it optional so that we can refer to it in the callback in 'init'
    private var audioKitPlayer: AKAudioPlayer? = nil

    /// Construction
    init?(viewController: ViewController, resourceUrl: URL) {
        // create and prepare player
        do {
            let audioFile = try AKAudioFile(forReading: resourceUrl)
            let player = try AKAudioPlayer(file: audioFile, looping: false, lazyBuffering: false)
            audioKitPlayer = player
            // attach
            viewController.attach(audioPlayer: player)
        } catch let ex {
            fatalError("coult not create audioplayer -> \(ex)")
            return nil
        }
    }

    /// Play audio file
    func schedulePlayback() {
        assert(AudioKit.engine.isRunning)
        guard let player = audioKitPlayer else { return }
        let avTime = AKAudioPlayer.secondsToAVAudioTime(hostTime: mach_absolute_time(), time: 1)
        player.play(from: 0, to: player.duration, avTime: avTime)
    }


    /// Pause playback
    func stop() {
        audioKitPlayer?.stop()
    }

}

extension UIButton {
    /// Disable / enable
    func setEnabled(_ enabled: Bool) {
        isUserInteractionEnabled = enabled
        alpha = enabled ? 1.0 : 0.5
    }
}
