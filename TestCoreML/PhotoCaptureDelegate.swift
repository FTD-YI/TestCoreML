/*
See LICENSE.txt for this sample’s licensing information.

Abstract:
Photo capture delegate.
*/

import AVFoundation
import Photos
import CoreML

class PhotoCaptureProcessor: NSObject {
	private(set) var requestedPhotoSettings: AVCapturePhotoSettings
	
	private let willCapturePhotoAnimation: () -> Void
	
	private let livePhotoCaptureHandler: (Bool) -> Void
	
	private let completionHandler: (PhotoCaptureProcessor) -> Void
	
	private var photoData: Data?
	
	private var livePhotoCompanionMovieURL: URL?
    
    private let model = Resnet50()

	init(with requestedPhotoSettings: AVCapturePhotoSettings,
	     willCapturePhotoAnimation: @escaping () -> Void,
	     livePhotoCaptureHandler: @escaping (Bool) -> Void,
	     completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
		self.requestedPhotoSettings = requestedPhotoSettings
		self.willCapturePhotoAnimation = willCapturePhotoAnimation
		self.livePhotoCaptureHandler = livePhotoCaptureHandler
		self.completionHandler = completionHandler
	}
	
	private func didFinish() {
		if let livePhotoCompanionMoviePath = livePhotoCompanionMovieURL?.path {
			if FileManager.default.fileExists(atPath: livePhotoCompanionMoviePath) {
				do {
					try FileManager.default.removeItem(atPath: livePhotoCompanionMoviePath)
				} catch {
					print("Could not remove file at url: \(livePhotoCompanionMoviePath)")
				}
			}
		}
		
		completionHandler(self)
	}
    
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    /*
     This extension includes all the delegate callbacks for AVCapturePhotoCaptureDelegate protocol
    */
    
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        if resolvedSettings.livePhotoMovieDimensions.width > 0 && resolvedSettings.livePhotoMovieDimensions.height > 0 {
            livePhotoCaptureHandler(true)
        }
        
        if let topController = UIApplication.shared.keyWindow?.rootViewController{
            let cameraVC = topController as! CameraViewController
            
            // Suspend Camera
            cameraVC.sessionQueue.async { [unowned cameraVC] in
                cameraVC.session.stopRunning()
                cameraVC.isSessionRunning = cameraVC.session.isRunning
            }
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            print("Error capturing photo: \(error)")
        } else {
            if let topController = UIApplication.shared.keyWindow?.rootViewController{
                let cameraVC = topController as! CameraViewController
                
                photoData = photo.fileDataRepresentation()
                
                // Change Data to Image
                guard let photoData = photoData else {
                    return
                }
                let image = UIImage(data: photoData)
                
                // Resize
                let newWidth:CGFloat = 224.0
                let newHeight:CGFloat = 224.0
                UIGraphicsBeginImageContext(CGSize(width:newWidth, height:newHeight))
                image?.draw(in:CGRect(x:0, y:0, width:newWidth, height:newHeight))
                let newImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                guard let finalImage = newImage else {
                    return
                }
                
                // Predicte
                guard let Resnet50CategoryOutput = try? model.prediction(image:pixelBufferFromImage(image: finalImage)) else {
                    fatalError("Unexpected runtime error.")
                }
                
                // Present with a alertView
                DispatchQueue.main.async { [unowned cameraVC] in
                    let alert = UIAlertController(title: "Category", message: Resnet50CategoryOutput.classLabel, preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler:{
                        action in
                        
                        // Resume Camera
                        cameraVC.sessionQueue.async { [unowned cameraVC] in
                            cameraVC.session.startRunning()
                            cameraVC.isSessionRunning = cameraVC.session.isRunning
                        }
                    }))
                    cameraVC.present(alert, animated: true, completion: nil)
                }
                
                
            }
            
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        livePhotoCaptureHandler(false)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error != nil {
            print("Error processing live photo companion movie: \(String(describing: error))")
            return
        }
        livePhotoCompanionMovieURL = outputFileURL
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            didFinish()
            return
        }
        
        guard let photoData = photoData else {
            print("No photo data resource")
            didFinish()
            return
        }
        
        // No need to save..
//        PHPhotoLibrary.requestAuthorization { [unowned self] status in
//            if status == .authorized {
//                PHPhotoLibrary.shared().performChanges({ [unowned self] in
//                    let options = PHAssetResourceCreationOptions()
//                    let creationRequest = PHAssetCreationRequest.forAsset()
//                    options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
//                    creationRequest.addResource(with: .photo, data: photoData, options: options)
//
//                    if let livePhotoCompanionMovieURL = self.livePhotoCompanionMovieURL {
//                        let livePhotoCompanionMovieFileResourceOptions = PHAssetResourceCreationOptions()
//                        livePhotoCompanionMovieFileResourceOptions.shouldMoveFile = true
//                        creationRequest.addResource(with: .pairedVideo, fileURL: livePhotoCompanionMovieURL, options: livePhotoCompanionMovieFileResourceOptions)
//                    }
//
//                    }, completionHandler: { [unowned self] _, error in
//                        if let error = error {
//                            print("Error occurered while saving photo to photo library: \(error)")
//                        }
//
//                        self.didFinish()
//                    }
//                )
//            } else {
//                self.didFinish()
//            }
//        }
    }
    
    func pixelBufferFromImage(image: UIImage) -> CVPixelBuffer {
        
        let ciimage = CIImage(image: image)
        //let cgimage = convertCIImageToCGImage(inputImage: ciimage!)
        let tmpcontext = CIContext(options: nil)
        let cgimage =  tmpcontext.createCGImage(ciimage!, from: ciimage!.extent)
        
        let cfnumPointer = UnsafeMutablePointer<UnsafeRawPointer>.allocate(capacity: 1)
        let cfnum = CFNumberCreate(kCFAllocatorDefault, .intType, cfnumPointer)
        let keys: [CFString] = [kCVPixelBufferCGImageCompatibilityKey, kCVPixelBufferCGBitmapContextCompatibilityKey, kCVPixelBufferBytesPerRowAlignmentKey]
        let values: [CFTypeRef] = [kCFBooleanTrue, kCFBooleanTrue, cfnum!]
        let keysPointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
        let valuesPointer =  UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
        keysPointer.initialize(to: keys)
        valuesPointer.initialize(to: values)
        
        let options = CFDictionaryCreate(kCFAllocatorDefault, keysPointer, valuesPointer, keys.count, nil, nil)
        
        let width = cgimage!.width
        let height = cgimage!.height
        
        var pxbuffer: CVPixelBuffer?
        // if pxbuffer = nil, you will get status = -6661
        var status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, options, &pxbuffer)
        status = CVPixelBufferLockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0));
        
        let bufferAddress = CVPixelBufferGetBaseAddress(pxbuffer!);
        
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB();
        let bytesperrow = CVPixelBufferGetBytesPerRow(pxbuffer!)
        let context = CGContext(data: bufferAddress,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesperrow,
                                space: rgbColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue);
        context?.concatenate(CGAffineTransform(rotationAngle: 0))
        context?.concatenate(__CGAffineTransformMake( 1, 0, 0, -1, 0, CGFloat(height) )) //Flip Vertical
        //        context?.concatenate(__CGAffineTransformMake( -1.0, 0.0, 0.0, 1.0, CGFloat(width), 0.0)) //Flip Horizontal
        
        
        context?.draw(cgimage!, in: CGRect(x:0, y:0, width:CGFloat(width), height:CGFloat(height)));
        status = CVPixelBufferUnlockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0));
        return pxbuffer!;
        
    }
}
