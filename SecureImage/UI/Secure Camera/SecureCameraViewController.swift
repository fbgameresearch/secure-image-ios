//
// SecureImage
//
// Copyright © 2017 Apple Inc. All rights reserved.
// Copyright © 2018 Province of British Columbia
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at 
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Created by Jason Leach on 2018-01-03.
//

import UIKit
import AVFoundation

typealias cameraAuthorizationCallback = ((_ authorized: Bool) -> Void)
typealias cameraSessionConfigurationCallback = ((_ success: Bool) -> Void)

protocol SecureCameraImageCaptureDelegate: class {
    
    func captured(image: Data)
}

class SecureCameraViewController: UIViewController {

    @IBOutlet weak var cameraPortalView: VideoPreviewView!
    @IBOutlet weak var cameraPortalOverlayView: UIView!
    @IBOutlet weak var previewViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var captureImageButton: UIButton!
    
    weak internal var delegate: SecureCameraImageCaptureDelegate?
    private let queue = {
        return DispatchQueue(label: "mySerialQueue")
    }()
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var inputDevice: AVCaptureDeviceInput?
    private var cameraOutput = AVCapturePhotoOutput()
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    override var shouldAutorotate: Bool {
        return false
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {

        super.viewDidLoad()
        
        cameraPortalView.session = session
        
        commonInit()
    }

    override func viewWillAppear(_ animated: Bool) {
        
        super.viewWillAppear(animated)
        
        guard !session.isRunning else { return }
        
        checkCameraAuthorization { authorized in
            
            guard authorized else {
                self.showCameraNotAuthorizationAlert()
                print("WARNING: Unable to use device camera.")

                return
            }
            
            self.startCamera()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        
        super.viewWillDisappear(animated)
        
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func commonInit() {
        
        captureImageButton.layer.cornerRadius = captureImageButton.bounds.width / 2
        previewViewHeightConstraint.constant = view.bounds.height / 2
        navigationController?.navigationBar.isHidden = true
        view.backgroundColor = UIColor.black
        cameraPortalOverlayView.alpha = 0.0
    }
    
    private func startCamera() {
        
        // This can take a while so it needs to be run serially on a
        // background thread
        self.queue.async {
            self.configureCaptureSession({ success in
                guard success else { return }
                self.session.startRunning()
                
                DispatchQueue.main.async {
                    // once we have the input device we can adjust the view port
                    // height to match
                    if let inputDevice = self.inputDevice {
                        self.adjustPreviewViewHeight(inputDevice: inputDevice)
                    }
                    
                    self.cameraPortalView.updateVideoOrientationForDeviceOrientation()
                }
            })
        }
    }

    private func configureCaptureSession(_ completionHandler: cameraSessionConfigurationCallback) {
        
        var success = false
        defer { completionHandler(success) }
        
        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                            mediaType: AVMediaType.video,
                                                            position: .back).devices.first else {
            print("WARNING: No video device found")
            return
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(device: device) else {
            print("Unable to obtain video input for default camera.")
            return
        }

        // output setup
        let cameraOutput = AVCapturePhotoOutput()
        cameraOutput.isHighResolutionCaptureEnabled = true
        cameraOutput.isLivePhotoCaptureEnabled = false
        
        // check input and output can be added to session
        guard session.canAddInput(videoInput) else { return }
        guard session.canAddOutput(cameraOutput) else { return }
        
        // session setup
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.photo
        session.addInput(videoInput)
        session.addOutput(cameraOutput)
        session.commitConfiguration()
        
        self.device = device
        self.inputDevice = videoInput
        self.cameraOutput = cameraOutput
        
        success = true
    }
    
    private func capture() {

        guard let connection = cameraPortalView.videoPreviewLayer.connection else { return }
        
        let videoPreviewLayerOrientation = connection.videoOrientation

        // Run this on our queue so that each opperation gets a chance to complete
        // and we are sure the session has started running
        queue.async {
            
            if let photoOutputConnection = self.cameraOutput.connection(with: AVMediaType.video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation
            }
            
            // The same photo settings can not be used to capture multiple
            // images
            let photoSettings = self.photoSettings()

            // didFinishProcessingPhoto must be implemented
            self.cameraOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
    private func adjustPreviewViewHeight(inputDevice: AVCaptureDeviceInput) {

        let resizeAnimationDuraiton = 0.2
        let scale = UIScreen.main.scale
        let dims = CMVideoFormatDescriptionGetDimensions(inputDevice.device.activeFormat.formatDescription)
        previewViewHeightConstraint.constant = (CGFloat(dims.height)/scale/2) - (navigationController?.navigationBar.frame.height ?? 0.0)

        view.setNeedsUpdateConstraints()
        
        UIView.animate(withDuration: resizeAnimationDuraiton) {
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction private func captureButtonTouched(sender: UIButton) {

        capture()
    }
    
    @IBAction private func focusTapDetected(sender: UIGestureRecognizer) {
        
        let poi = (cameraPortalView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointConverted(fromLayerPoint: sender.location(in: cameraPortalView))
        focus(at: poi)
    }
    
    @IBAction private func flashOnTouched(sender: UIGestureRecognizer) {

        flashMode = .on
    }
    
    @IBAction private func flashOffTouched(sender: UIGestureRecognizer) {

        flashMode = .off
    }
    
    @IBAction private func flashAutoTouched(sender: UIGestureRecognizer) {

        flashMode = .auto
    }
    
    // MARK: Photo Settings
    
    private func photoSettings() -> AVCapturePhotoSettings {
        
        let compression = [AVVideoQualityKey : NSNumber(value: Constants.Defaults.jPEGCompressionRatio)]
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecJPEG,
                                                       AVVideoCompressionPropertiesKey: compression])

        settings.flashMode = flashMode
        
        return settings
    }
    
    private func focus(at point: CGPoint, focusMode: AVCaptureDevice.FocusMode = .autoFocus,
                       exposureMode: AVCaptureDevice.ExposureMode = .autoExpose) {
        
        queue.async {
        
            guard let inputDevice = self.inputDevice, let _ = try? inputDevice.device.lockForConfiguration() else {
                print("Unable to obtain lock for input device configuration")
                return
            }
            
            defer { inputDevice.device.unlockForConfiguration() }

            // The default Focus and Exposure modes are .continuousAutoFocus and
            // .continuousAutoExposure. This needs to be tweaked if we're goin to
            // set a focal point.
  
            if inputDevice.device.isFocusPointOfInterestSupported {
                inputDevice.device.focusPointOfInterest = point
                inputDevice.device.focusMode = focusMode
            }
            
            if inputDevice.device.isExposurePointOfInterestSupported {
                inputDevice.device.exposurePointOfInterest = point
                inputDevice.device.exposureMode = exposureMode
            }
        }
    }
    
    private func performImageCapturedAnimations() {

        let fadeInAnimationDuration = 0.1
        let fadeOutAnimationDuration = 0.2
        
        UIView.animate(withDuration: fadeInAnimationDuration, animations: {
            self.cameraPortalOverlayView.alpha = 0.7
        }, completion: { success in
            UIView.animate(withDuration: fadeOutAnimationDuration, animations: {
                self.cameraPortalOverlayView.alpha = 0
            })
        })
    }

    // MARK: Cemera Authorization
    
    private func checkCameraAuthorization(_ completionHandler: @escaping cameraAuthorizationCallback) {

        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .notDetermined:
            // access must be requested
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { success in
                completionHandler(success)
            })
        case .authorized:
            // previously authorized
            completionHandler(true)
        case .denied:
            // previously denied
            completionHandler(false)
        case .restricted:
            // no user accesss e.g. parental restriction.
            completionHandler(false)
        }
    }
    
    private func showCameraNotAuthorizationAlert() {
        let title = "Camera Access"
        let message = """
            You have not given permission for this application to use the camera.
            You can change this by going to Settings -> Privacy -> Camera and granting permission.
        """
        
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let cancel = UIAlertAction(title: "Ok", style: .cancel, handler: nil)

        ac.addAction(cancel)
        
        present(ac, animated: true, completion: nil)
    }
}

// MARK: AVCapturePhotoCaptureDelegate
extension SecureCameraViewController: AVCapturePhotoCaptureDelegate {

    /* This is the order delegate methods are called:
        willBeginCaptureForResolvedSettings
        willCapturePhotoForResolvedSettings
        didCapturePhotoForResolvedSettings
        didFinishProcessingPhotoSampleBuffer
        didFinishCaptureForResolvedSettings
     */

    func photoOutput(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?, previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        
        if let error = error {
            print(error.localizedDescription)
        }
    
        // previewPhotoSampleBuffer may be nil, and that's ok.

        if let sampleBuffer = photoSampleBuffer, let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: sampleBuffer, previewPhotoSampleBuffer: previewPhotoSampleBuffer) {

            performImageCapturedAnimations()
            
            delegate?.captured(image: data)
        }
    }
}
