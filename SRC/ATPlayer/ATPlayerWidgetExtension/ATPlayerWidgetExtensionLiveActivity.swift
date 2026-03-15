//
//  ATPlayerWidgetExtensionLiveActivity.swift
//  ATPlayerWidgetExtension
//
//  Created by Andrey Torlopov on 15.03.2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ATPlayerWidgetExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ATPlayerWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ATPlayerWidgetExtensionAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ATPlayerWidgetExtensionAttributes {
    fileprivate static var preview: ATPlayerWidgetExtensionAttributes {
        ATPlayerWidgetExtensionAttributes(name: "World")
    }
}

extension ATPlayerWidgetExtensionAttributes.ContentState {
    fileprivate static var smiley: ATPlayerWidgetExtensionAttributes.ContentState {
        ATPlayerWidgetExtensionAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ATPlayerWidgetExtensionAttributes.ContentState {
         ATPlayerWidgetExtensionAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ATPlayerWidgetExtensionAttributes.preview) {
   ATPlayerWidgetExtensionLiveActivity()
} contentStates: {
    ATPlayerWidgetExtensionAttributes.ContentState.smiley
    ATPlayerWidgetExtensionAttributes.ContentState.starEyes
}
