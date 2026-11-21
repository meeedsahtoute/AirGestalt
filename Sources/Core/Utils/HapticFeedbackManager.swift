//
//  HapticFeedbackManager.swift
//  AirGestalt
//
//  Tactile haptic feedback wrappers using UIImpactFeedbackGenerator
//  and UINotificationFeedbackGenerator for native Apple-feel controls.
//

import UIKit

public final class HapticFeedbackManager {
    public static let shared = HapticFeedbackManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private init() {
        prepare()
    }

    public func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        selectionFeedback.prepare()
        notificationFeedback.prepare()
    }

    public func modeChanged() {
        mediumImpact.impactOccurred()
    }

    public func selectionChanged() {
        selectionFeedback.selectionChanged()
    }

    public func pairingSuccess() {
        notificationFeedback.notificationOccurred(.success)
    }

    public func warning() {
        notificationFeedback.notificationOccurred(.warning)
    }

    public func error() {
        notificationFeedback.notificationOccurred(.error)
    }

    public func buttonTap() {
        lightImpact.impactOccurred()
    }
}
