//
//  ChatView.swift
//  ChatGPTExample
//
//  Created by Jaesung Lee on 2023/02/16.
//

import ChatUI
import SwiftUI

struct ChatView: View {
    @StateObject private var chatGPT = ChatGPT()
    var body: some View {
        VStack(spacing: 0) {
            MessageList(chatGPT.messages) { message in
                GPTMessageRow(
                    message: message,
                    isLastMessage: chatGPT.messages.first == message
                )
                .padding(.top, 12)
            }

            MessageField(
                options: [],
                showsSendButtonAlways: true
            ) { messageStyle in
                chatGPT.sendMesssage(forStyle: messageStyle)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ChatView()
                .environmentObject(ChatConfiguration(userID: User.me.id))
                .environment(
                    \.appearance,
                    Appearance(
                        tint: Color(red: 0, green: 166 / 255, blue: 126 / 255),
                        localMessageBackground: Color(
                            red: 0,
                            green: 166 / 255,
                            blue: 126 / 255
                        )
                    )
                )
        }
    }
}
