//
//  ViewController.swift
//  AudioKitSampleRate
//
//  Created by Martin Mlostek on 22.08.19.
//  Copyright © 2019 nomad5. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    /// Ui stuff
    @IBOutlet weak var startVP1:         UIButton!
    @IBOutlet weak var startVP2:         UIButton!
    @IBOutlet weak var startVP3:       UIButton!
    @IBOutlet weak var startNoVP1:       UIButton!
    @IBOutlet weak var stopButton:       UIButton!
    @IBOutlet weak var debugLabel:       UILabel!

    /// Instance of the AKPlayer
    private var        audioPlayer:      AudioAVPlayer? = nil

    /// Audio input mapper
    private let        audioInputMapper: AudioInputMapper

    /// Default constructor, shall not pass
    required init?(coder aDecoder: NSCoder) {
        audioInputMapper = AudioInputMapper()
        super.init(coder: aDecoder)
    }

    /// Just observe some stuff
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Timer.scheduledTimer(withTimeInterval: 0.1,
                             repeats: true) { [weak self] _ in
            let session = AVAudioSession.sharedInstance()
            self?.debugLabel.text = """
                                    sampleRate : \(session.sampleRate)
                                    mode       : \(session.mode.rawValue)
                                    inputGain  : \(session.inputGain)
                                    category   : \(session.category.rawValue)
                                    cat options: \(session.categoryOptions.rawValue)
                                    """
        }
    }

    @IBAction func onStartVP1(_ sender: Any) {
        self.switchButtons(false)
        createAudio()
        playAudio()
        startEngine(true)
    }

    @IBAction func onStartVP2(_ sender: Any) {
        self.switchButtons(false)
        createAudio()
        startEngine(true)
        playAudio()
    }

    @IBAction func onStartVP3(_ sender: Any) {
        self.switchButtons(false)
        startEngine(true)
        createAudio()
        playAudio()
    }

    @IBAction func onStartNoVP1(_ sender: Any) {
        self.switchButtons(false)
        startEngine(false)
        createAudio()
        playAudio()
    }

    @IBAction func onStop(_ sender: Any) {
        stopButton.setEnabled(false)
        switchButtons(true)
        // reset
        audioPlayer?.stop()
        audioPlayer = nil
        audioInputMapper.stop()
        audioInputMapper.tearDown()
    }

    /// Start engine
    func startEngine(_ voiceProcessing: Bool) {
        // start
        do {
            // configure session
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
            try AVAudioSession.sharedInstance().setActive(true)
            // setup and start input mapper
            audioInputMapper.setup(voiceProcessing)
            audioInputMapper.start()
        } catch {
            fatalError("could not setup audio")
        }
    }

    /// Create audio
    func createAudio() {
        // reset
        audioPlayer?.stop()
        audioPlayer = nil
        // restart
        let url = Bundle.main.url(forResource: "sound", withExtension: "wav")!
        audioPlayer = AudioAVPlayer(resourceUrl: url)
    }

    /// Start audio
    func playAudio() {
        audioPlayer?.play()
        stopButton.setEnabled(true)
    }

    /// Disable all buttons except the given one
    private func switchButtons(_ enable: Bool) {
        startVP1.setEnabled(enable)
        startVP2.setEnabled(enable)
        startVP3.setEnabled(enable)
        startNoVP1.setEnabled(enable)
        stopButton.setEnabled(!enable)
    }
}


/// AVFoundation implementation
class AudioAVPlayer {

    /// Instance of the AKPlayer
    private let player: AVAudioPlayer

    /// Construction
    init?(resourceUrl: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: resourceUrl)
            player.volume = 1.0
            player.prepareToPlay()
        } catch {
            print("File Not Found")
            return nil
        }
    }

    /// Play audio file
    func play() {
        player.currentTime = 0
        player.play()
    }

    /// Pause playback
    func stop() {
        player.stop()
    }
}

extension UIButton {
    /// Disable / enable
    func setEnabled(_ enabled: Bool) {
        isUserInteractionEnabled = enabled
        alpha = enabled ? 1.0 : 0.5
    }
}
