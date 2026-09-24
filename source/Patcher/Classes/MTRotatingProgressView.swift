/*
    MTRotatingProgressView.swift
    Copyright 2026 SAP SE
     
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
     
    http://www.apache.org/licenses/LICENSE-2.0
     
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

import AppKit
import QuartzCore

final class MTRotatingProgressView: NSView {
    
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var tableCellView: NSTableCellView!
    
    private var cellObservation: NSKeyValueObservation?
    private var applicationObservations: [NSKeyValueObservation] = []
    
    private let rotationAnimationKey = "corp.sap.Patcher.rotatingProgressView.rotation"
    private let rotationAnchorPoint = CGPoint(x: 0.5, y: 0.5)
    
    private var lastConfiguredLayerBoundsSize: CGSize = .zero
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        wantsLayer = true

        configureRotatingLayerIfNeeded(force: true)
                
        observeTableCellView()
        updateProgressIndicator()
    }
    
    override func layout() {
        super.layout()
        
        configureRotatingLayerIfNeeded()
    }
    
    override func viewDidMoveToWindow() {
        
        super.viewDidMoveToWindow()
        
        if window == nil {
            stopRotating()
        } else {
            configureRotatingLayerIfNeeded(force: true)
            updateProgressIndicator()
        }
    }
    
    deinit {
        stopRotating()
        cellObservation = nil
        applicationObservations.removeAll()
    }
    
    private func observeTableCellView() {
        
        cellObservation = tableCellView.observe(
            \.objectValue,
             options: [.initial, .new]
        ) { [weak self] cellView, _ in
            
            DispatchQueue.main.async {
                self?.observeApplication(cellView.objectValue as? MTApplication)
                self?.updateProgressIndicator()
            }
        }
    }
    
    private func observeApplication(_ application: MTApplication?) {
        
        applicationObservations.removeAll()
        
        guard let application else { return }
        
        applicationObservations = [
            application.observe(\.isInstalling, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.updateProgressIndicator()
                }
            },
            application.observe(\.installProgress, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.updateProgressIndicator()
                }
            }
        ]
    }
    
    private func updateProgressIndicator() {
        
        guard let application = tableCellView?.objectValue as? MTApplication else {
            stopRotating()
            return
        }
        
        guard application.isInstalling else {
            stopRotating()
            return
        }
                
        if application.isInstalling && application.installProgress == 1 {
            
            progressIndicator.doubleValue = 0.25
            startRotating()
            
        } else {
            
            stopRotating()
            progressIndicator.doubleValue = Double(application.installProgress)
        }
    }
    
    private func startRotating() {
        
        wantsLayer = true
        configureRotatingLayerIfNeeded()
        
        guard let layer else { return }
        guard layer.animation(forKey: rotationAnimationKey) == nil else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.byValue = -Double.pi * 2
        animation.duration = 1.5
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        
        layer.add(animation, forKey: rotationAnimationKey)
    }
    
    private func stopRotating() {
        
        guard let layer else { return }
        
        layer.removeAnimation(forKey: rotationAnimationKey)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }
    
    private func configureRotatingLayerIfNeeded(force: Bool = false) {
        
        guard let layer else { return }
        
        let needsConfiguration = force || layer.anchorPoint != rotationAnchorPoint || layer.bounds.size != lastConfiguredLayerBoundsSize
        
        guard needsConfiguration else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let currentFrame = layer.frame
        
        layer.anchorPoint = rotationAnchorPoint
        layer.frame = currentFrame
        layer.masksToBounds = false
        
        lastConfiguredLayerBoundsSize = layer.bounds.size
        
        CATransaction.commit()
    }
}
