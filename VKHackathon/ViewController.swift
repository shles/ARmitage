//
//  AppDelegate.swift
//  VKHackathon
//
//  Created by Timofey on 10/20/17.
//  Copyright © 2017 NFO. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision
import RxSwift
import RxCocoa

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
    
    class RedView: UIView {
        
        init() {
            super.init(frame: .init(x: 0, y: 0, width: 10, height: 10))
            backgroundColor = .red
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
    }
    
    // MARK: - Properties
    
    @IBOutlet var sceneView: ARSCNView!
    
    var detectedDataAnchor: ARAnchor?
    var processing = false
    
    // MARK: - View Setup
    
    let topLeftView = RedView()
    let bottomLeftView = RedView()
    let topRightView = RedView()
    let bottomRightView = RedView()
    
    let redView = UIView()
    
    let tapGR = UITapGestureRecognizer()
    let pressGR = UILongPressGestureRecognizer()
    
    @IBOutlet var segmentedControl: UISegmentedControl!
    
    private let disposeBag = DisposeBag()
    
    private let holdRelay = Variable(true)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let cupSceneChildNodes = SCNScene(named: "cup.scn", inDirectory: "art.scnassets/cup")!.rootNode.childNodes
        let overlayChildNodes = SCNScene(named: "overlay.scn", inDirectory: "art.scnassets")!.rootNode.childNodes
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Set the session's delegate
        sceneView.session.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        sceneView.addSubview(redView)
        sceneView.addSubview(topLeftView)
        sceneView.addSubview(topRightView)
        sceneView.addSubview(bottomLeftView)
        sceneView.addSubview(bottomRightView)
        redView.backgroundColor = .red
        redView.frame.size = .init(width: 10, height: 10)
        
        view.isUserInteractionEnabled = true
        sceneView.isUserInteractionEnabled = true
        sceneView.addGestureRecognizer(pressGR)
        sceneView.addGestureRecognizer(tapGR)
        
        pressGR.delegate = self
        pressGR.rx.event.map{ gr -> Bool in
            switch gr.state {
            case .began, .changed: return false
            case .ended: return true
            default: return true
            }
            }.bind(to: holdRelay).disposed(by: disposeBag)
        
        view.addSubview(segmentedControl)
        segmentedControl.rx.value.subscribe(onNext: { value in
            guard let anchor = self.detectedDataAnchor else { return }
            let node = self.sceneView.node(for: anchor)
            node?.childNodes.forEach{ $0.removeFromParentNode() }
            
            let scene: [SCNNode]
            switch value {
            case 0: scene = overlayChildNodes
            case 1: scene = cupSceneChildNodes
            default: scene = []
            }
            
            for child in scene {
                child.geometry?.firstMaterial?.lightingModel = .physicallyBased
                child.movabilityHint = .fixed
                node?.addChildNode(child)
            }

        }).disposed(by: disposeBag)
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Enable horizontal plane detection
        configuration.planeDetection = .horizontal
        
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    
    // MARK: - ARSessionDelegate
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        // Only run one Vision request at a time
        if self.processing || holdRelay.value {
            return
        }
        
        self.processing = true
        
        // Create a Barcode Detection Request
        let request = VNDetectRectanglesRequest { (request, error) in
            
            // Get the first result out of the results, if there are any
            let results = request.results?.flatMap{ $0 as? VNRectangleObservation }
            if let result = results?.first(where: { observation in
                //                observation.boundingBox.contains(
                //                    CGRect(
                //                        x: 0.3,
                //                        y: 0.3,
                //                        width: 0.4,
                //                        height: 0.4
                //                    )
                //                ) && CGRect(
                //                    x: 0.1,
                //                    y: 0.1,
                //                    width: 0.8,
                //                    height: 0.8
                //                ).contains(observation.boundingBox)
                return true
            }) {
                
                // Get the bounding box for the bar code and find the center
                var rect = result.boundingBox
                
                // Flip coordinates
                rect = rect.applying(CGAffineTransform(scaleX: 1, y: -1))
                rect = rect.applying(CGAffineTransform(translationX: 0, y: 1))
                
                // Get center
                let center = CGPoint(x: rect.midX, y: rect.midY)
                // Go back to the main thread
                DispatchQueue.main.async { [unowned self] in
                    
                    [
                        (self.redView, center),
                        (self.bottomLeftView, center.applying(
                            CGAffineTransform(translationX: -rect.width/2, y: -rect.height/2)
                            )
                        ),
                        (self.bottomRightView, center.applying(
                            CGAffineTransform(translationX: rect.width/2, y: -rect.height/2)
                        )),
                        (self.topLeftView, center.applying(
                            CGAffineTransform(translationX: -rect.width/2, y: rect.height/2)
                        )),
                        (self.topRightView, center.applying(
                            CGAffineTransform(translationX: rect.width/2, y: rect.height/2)
                        ))
                        ].forEach{ view, point in
                            view.frame.origin.x = self.view.frame.width * point.x
                            view.frame.origin.y = self.view.frame.height * point.y
                    }
                    
                    //                     Perform a hit test on the ARFrame to find a surface
                    let hitTestResults = frame.hitTest(center, types: [.featurePoint/*, .estimatedHorizontalPlane, .existingPlane, .existingPlaneUsingExtent*/] )
                    
                    // If we have a result, process it
                    //                    print(hitTestResults.map{ $0.distance })
                    if let hitTestResult = hitTestResults.first {
                        
                        hitTestResult.worldTransform
                        // If we already have an anchor, update the position of the attached node
                        if let detectedDataAnchor = self.detectedDataAnchor,
                            let node = self.sceneView.node(for: detectedDataAnchor) {
                            
                            let rotate = simd_float4x4(SCNMatrix4MakeRotation(self.sceneView.session.currentFrame!.camera.eulerAngles.y, 0, 1, 0))
                            
                            // Combine both transformation matrices
                            let finalTransform = simd_mul(hitTestResult.worldTransform, rotate)
                            node.transform = SCNMatrix4(finalTransform)
//                            node.scale = SCNVector3(
//                                hitTestResult.distance/rect.width,
//                                hitTestResult.distance/rect.height,
//                                1
//                            )
//                            node.transform.m22 = Float(rect.width)
//                            node.transform.m33 = Float(rect.height)
//                            node.sc
                            
//                            node.eulerAngles = SCNVector3(0,
//                                                          hitTestResult.worldTransform[3][1],
//                                                          0)
                        } else {
                            // Create an anchor. The node will be created in delegate methods
                            self.detectedDataAnchor = ARAnchor(transform: hitTestResult.worldTransform)
                            self.sceneView.session.add(anchor: self.detectedDataAnchor!)
                        }
                    }
                    
                    // Set processing flag off
                    self.processing = false
                }
                
            } else {
                // Set processing flag off
                self.processing = false
            }
        }
        
        //         Process the request in the background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create a request handler using the captured image from the ARFrame
                let imageRequestHandler = VNImageRequestHandler(
                    cvPixelBuffer: frame.capturedImage,
                    options: [:]
                )
                // Process the request
                try imageRequestHandler.perform([request])
            } catch {
                
            }
        }
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        
        // If this is our anchor, create a node
        if self.detectedDataAnchor?.identifier == anchor.identifier {
            
            // Create a 3D Cup to display
            guard let virtualObjectScene = SCNScene(named: "overlay.scn", inDirectory: "art.scnassets") else {
                print("failed to open model")
                return nil
            }
            
            let wrapperNode = SCNNode()
            
            for child in virtualObjectScene.rootNode.childNodes {
                child.geometry?.firstMaterial?.lightingModel = .physicallyBased
                child.movabilityHint = .fixed
                wrapperNode.addChildNode(child)
            }
            
            // Set its position based off the anchor
            wrapperNode.transform = SCNMatrix4(anchor.transform)
            
            return wrapperNode
        }
        
        return nil
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
}

