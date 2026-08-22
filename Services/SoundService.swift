//
//  SoundService.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation
import AVFoundation

class SoundService {
    static let shared = SoundService()
    
    private var audioPlayer: AVAudioPlayer?
    
    private init() {
        // Configure audio session for sound playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }
    
    func playSound(named fileName: String, withExtension ext: String = "mp3") {
        // Try to find the sound file in the bundle
        var soundURL: URL?
        
        // First try root bundle
        if let url = Bundle.main.url(forResource: fileName, withExtension: ext) {
            soundURL = url
        }
        // If not found, try in Sound subfolder
        else if let url = Bundle.main.url(forResource: fileName, withExtension: ext, subdirectory: "Sound") {
            soundURL = url
        }
        // If still not found, try without subdirectory but with full path
        else if let url = Bundle.main.url(forResource: "Sound/\(fileName)", withExtension: ext) {
            soundURL = url
        }
        
        guard let url = soundURL else {
            print("❌ Sound file not found: \(fileName).\(ext) (checked root, Sound subfolder, and Sound/\(fileName).\(ext))")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("🔊 Playing sound: \(fileName).\(ext)")
        } catch {
            print("❌ Failed to play sound: \(error)")
        }
    }
    
    func playNewMessageSound() {
        playSound(named: "newMessage", withExtension: "mp3")
    }
    
    func playMatchSound() {
        playSound(named: "Match", withExtension: "mp3")
    }
}

