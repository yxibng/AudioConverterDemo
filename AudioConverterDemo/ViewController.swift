//
//  ViewController.swift
//  AudioConverterDemo
//
//  Created by xiaobing yao on 2022/12/7.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    let captureSession = AVCaptureSession()

    let handler = TSAudioHandler.init()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.record)
            try AVAudioSession.sharedInstance().setPreferredSampleRate(48000)
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.2)
        } catch {
            print(error)
            return
        }

        // Find the default audio device.
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else { return }

        do {
            // Wrap the audio device in a capture device input.
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            // If the input can be added, add it to the session.
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
        } catch {
            // Configuration failed. Handle error.
        }
        
        let output = AVCaptureAudioDataOutput.init()
        output.setSampleBufferDelegate(self, queue: .init(label: "audio.output.queue"))
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }
        
        
        // Do any additional setup after loading the view.
    }

    @IBAction func onClickStart(_ sender: Any) {
        self.captureSession .startRunning()
    }
    
    @IBAction func onClickStop(_ sender: Any) {
        self.captureSession.stopRunning()
    }
}

extension ViewController: AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        self.handler.receiveAudioSampleBuffer(sampleBuffer)
    }
    
}

