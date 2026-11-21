//
//  AirPods3DView.swift
//  AirGestalt
//
//  Procedural 3D Earbuds & Case rendering using SceneKit.
//  Zero external .usdz dependencies.
//  Features physically-based glossy shaders, chrome charging rings,
//  acoustic mesh grills, LED indicator, and interactive 360-degree rotation.
//

import SwiftUI
import SceneKit

public struct AirPods3DView: UIViewRepresentable {
    public var isCaseMode: Bool = false
    public var isCharging: Bool = false

    public init(isCaseMode: Bool = false, isCharging: Bool = false) {
        self.isCaseMode = isCaseMode
        self.isCharging = isCharging
    }

    public func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = true
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        scnView.scene = scene

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 48
        cameraNode.position = SCNVector3(0, 0, isCaseMode ? 5.2 : 4.4)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting setup: Key light, Fill light, and Ambient light
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1200
        keyLight.light?.color = UIColor.white
        keyLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .omni
        fillLight.light?.intensity = 600
        fillLight.position = SCNVector3(-3, 3, 2)
        scene.rootNode.addChildNode(fillLight)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 350
        ambientLight.light?.color = UIColor(white: 0.9, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        // Build procedural 3D model
        let rootModelNode = SCNNode()
        rootModelNode.name = "rootModel"

        if isCaseMode {
            rootModelNode.addChildNode(createProceduralCase(isCharging: isCharging))
        } else {
            let leftEarbud = createProceduralEarbud(isLeft: true)
            leftEarbud.position = SCNVector3(-0.7, 0, 0)
            let rightEarbud = createProceduralEarbud(isLeft: false)
            rightEarbud.position = SCNVector3(0.7, 0, 0)
            rootModelNode.addChildNode(leftEarbud)
            rootModelNode.addChildNode(rightEarbud)
        }

        scene.rootNode.addChildNode(rootModelNode)

        // Idle slow auto-rotation animation
        let spinAction = SCNAction.rotateBy(x: 0, y: CGFloat(Float.pi * 2), z: 0, duration: 18.0)
        let repeatAction = SCNAction.repeatForever(spinAction)
        rootModelNode.runAction(repeatAction)

        return scnView
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {
        // Dynamic updates if needed
    }

    // MARK: - Procedural Earbud Geometry Construction

    private func createProceduralEarbud(isLeft: Bool) -> SCNNode {
        let earbudNode = SCNNode()

        // Glossy White Material
        let whiteGlossy = SCNMaterial()
        whiteGlossy.lightingModel = .physicallyBased
        whiteGlossy.diffuse.contents = UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0)
        whiteGlossy.roughness.contents = 0.08
        whiteGlossy.metalness.contents = 0.04

        // Chrome Ring Material
        let chromeMetal = SCNMaterial()
        chromeMetal.lightingModel = .physicallyBased
        chromeMetal.diffuse.contents = UIColor(white: 0.85, alpha: 1.0)
        chromeMetal.metalness.contents = 0.95
        chromeMetal.roughness.contents = 0.05

        // Black Mesh Material
        let blackMesh = SCNMaterial()
        blackMesh.lightingModel = .physicallyBased
        blackMesh.diffuse.contents = UIColor(white: 0.12, alpha: 1.0)
        blackMesh.roughness.contents = 0.75
        blackMesh.metalness.contents = 0.1

        // 1. Acoustic Chamber / Head (Deformed Sphere)
        let headGeo = SCNSphere(radius: 0.44)
        headGeo.materials = [whiteGlossy]
        let headNode = SCNNode(geometry: headGeo)
        headNode.scale = SCNVector3(1.0, 1.15, 0.92)
        headNode.position = SCNVector3(0, 0.65, 0)
        earbudNode.addChildNode(headNode)

        // 2. Ear Tip (Silicone oval)
        let tipGeo = SCNSphere(radius: 0.32)
        let tipMaterial = SCNMaterial()
        tipMaterial.lightingModel = .physicallyBased
        tipMaterial.diffuse.contents = UIColor(white: 0.95, alpha: 1.0)
        tipMaterial.roughness.contents = 0.45
        tipGeo.materials = [tipMaterial]
        let tipNode = SCNNode(geometry: tipGeo)
        tipNode.scale = SCNVector3(0.85, 1.05, 0.7)
        let tipOffset: Float = isLeft ? 0.32 : -0.32
        tipNode.position = SCNVector3(tipOffset, 0.72, 0.28)
        tipNode.eulerAngles = SCNVector3(0, isLeft ? Float.pi / 6 : -Float.pi / 6, 0)
        earbudNode.addChildNode(tipNode)

        // 3. Acoustic Mesh Vent
        let ventGeo = SCNCapsule(capRadius: 0.06, height: 0.22)
        ventGeo.materials = [blackMesh]
        let ventNode = SCNNode(geometry: ventGeo)
        ventNode.position = SCNVector3(0, 0.88, -0.22)
        ventNode.eulerAngles = SCNVector3(Float.pi / 3, 0, 0)
        earbudNode.addChildNode(ventNode)

        // 4. Stem
        let stemGeo = SCNCylinder(radius: 0.12, height: 1.15)
        stemGeo.materials = [whiteGlossy]
        let stemNode = SCNNode(geometry: stemGeo)
        stemNode.position = SCNVector3(0, 0.0, 0)
        stemNode.eulerAngles = SCNVector3(0, 0, isLeft ? -0.08 : 0.08)
        earbudNode.addChildNode(stemNode)

        // 5. Force Sensor Indentation on Stem
        let sensorGeo = SCNCapsule(capRadius: 0.04, height: 0.28)
        sensorGeo.materials = [blackMesh]
        let sensorNode = SCNNode(geometry: sensorGeo)
        sensorNode.position = SCNVector3(isLeft ? 0.09 : -0.09, 0.05, 0.06)
        earbudNode.addChildNode(sensorNode)

        // 6. Chrome Charging Contact Ring at Base
        let ringGeo = SCNCylinder(radius: 0.122, height: 0.08)
        ringGeo.materials = [chromeMetal]
        let ringNode = SCNNode(geometry: ringGeo)
        ringNode.position = SCNVector3(0, -0.56, 0)
        earbudNode.addChildNode(ringNode)

        return earbudNode
    }

    // MARK: - Procedural Charging Case Construction

    private func createProceduralCase(isCharging: Bool) -> SCNNode {
        let caseRoot = SCNNode()

        let whiteGlossy = SCNMaterial()
        whiteGlossy.lightingModel = .physicallyBased
        whiteGlossy.diffuse.contents = UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0)
        whiteGlossy.roughness.contents = 0.06
        whiteGlossy.metalness.contents = 0.02

        // Main Case Body (Chamfered Box)
        let bodyGeo = SCNBox(width: 1.9, height: 1.45, length: 0.78, chamferRadius: 0.35)
        bodyGeo.materials = [whiteGlossy]
        let bodyNode = SCNNode(geometry: bodyGeo)
        caseRoot.addChildNode(bodyNode)

        // Lid Seam
        let seamGeo = SCNBox(width: 1.92, height: 0.015, length: 0.80, chamferRadius: 0.0)
        let seamMaterial = SCNMaterial()
        seamMaterial.diffuse.contents = UIColor(white: 0.75, alpha: 1.0)
        seamGeo.materials = [seamMaterial]
        let seamNode = SCNNode(geometry: seamGeo)
        seamNode.position = SCNVector3(0, 0.28, 0)
        caseRoot.addChildNode(seamNode)

        // Front LED Status Light
        let ledGeo = SCNSphere(radius: 0.035)
        let ledMaterial = SCNMaterial()
        ledMaterial.lightingModel = .constant
        let ledColor = isCharging ? UIColor.systemOrange : UIColor.systemGreen
        ledMaterial.diffuse.contents = ledColor
        ledMaterial.emission.contents = ledColor
        ledGeo.materials = [ledMaterial]
        let ledNode = SCNNode(geometry: ledGeo)
        ledNode.position = SCNVector3(0, 0.02, 0.40)
        caseRoot.addChildNode(ledNode)

        // Bottom Chrome USB-C / Lightning Port Ring
        let portRing = SCNCapsule(capRadius: 0.05, height: 0.24)
        let chromeMaterial = SCNMaterial()
        chromeMaterial.lightingModel = .physicallyBased
        chromeMaterial.metalness.contents = 0.95
        chromeMaterial.roughness.contents = 0.08
        portRing.materials = [chromeMaterial]
        let portNode = SCNNode(geometry: portRing)
        portNode.position = SCNVector3(0, -0.73, 0)
        portNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        caseRoot.addChildNode(portNode)

        return caseRoot
    }
}
