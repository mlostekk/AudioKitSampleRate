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

    var player: AVPlayer?
    var audioPlayer: AKAudioPlayer?
    var mixer: AKMixer  = AKMixer()
    var timer: Timer!

    @IBOutlet weak var videoContainer: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _  in
            print("samplerate: \(AVAudioSession.sharedInstance().sampleRate)")
        }
        AKSettings.sampleRate = 16000.0
        AKSettings.defaultToSpeaker = true
        AudioKit.output = mixer
        try! AudioKit.start()

    }

    func setupAudio() {
        audioPlayer?.stop()
        let file = try! AKAudioFile(forReading: Bundle.main.url(forResource: "sound", withExtension: "wav")!)
        audioPlayer = try! AKAudioPlayer(file: file, looping: false, lazyBuffering: false)
        mixer.connect(input: audioPlayer)
        // play audio
        audioPlayer!.play(from: 0)

    }

    func setupVideo() {
        // remove
        videoContainer.layer.sublayers = nil;
        // add
        let asset =         AVURLAsset(url: Bundle.main.url(forResource: "bunny", withExtension: "mp4")!)
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.frame = videoContainer.frame
        videoContainer.layer.addSublayer(layer)
        player?.seek(to: CMTimeMake(value: 0, timescale: 1000))
        player?.play()

    }

    @IBAction func onButtonPress(_ sender: Any) {
        setupVideo()
        setupAudio()
    }
}

