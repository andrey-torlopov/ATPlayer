//
//  ATPlayerWidgetExtensionBundle.swift
//  ATPlayerWidgetExtension
//
//  Created by Andrey Torlopov on 15.03.2026.
//

import WidgetKit
import SwiftUI

@main
struct ATPlayerWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        ATPlayerWidgetExtension()
        ATPlayerWidgetExtensionControl()
        ATPlayerWidgetExtensionLiveActivity()
    }
}
