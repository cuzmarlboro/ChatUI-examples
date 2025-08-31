//
//  ChatGPT.swift
//  ChatGPTExample
//
//  Created by Jaesung Lee on 2023/02/21.
//

import ChatUI
import SwiftUI

class ChatGPT: ObservableObject {
  @Published var messages: [Message] = []
  private let networkManager = NetworkManager()

  func sendMesssage(forStyle style: MessageStyle) {
    switch style {
    case .text(let text):
      let localMessage = Message(
        id: UUID().uuidString,
        sentAt: Date().timeIntervalSince1970,
        readReceipt: .seen,
        style: style,
        sender: User.me
      )
      withAnimation {
        messages.insert(localMessage, at: 0)
      }
      /// Get response for ChatGPT
      requestResponse(for: text)
    default: return
    }
  }

  /// 发送真实请求到ChatGPT API
  func requestResponse(for text: String) {
    // 1) 先插入一个空的机器人消息，稍后逐字填充
    let botId = UUID().uuidString
    let placeholder = Message(
      id: botId,
      sentAt: Date().timeIntervalSince1970,
      readReceipt: .seen,
      style: .text(""),
      sender: User.chatBot
    )
    DispatchQueue.main.async {
      withAnimation {
        self.messages.insert(placeholder, at: 0)
      }
    }

    // 2) 使用NetworkManager发送真实请求
    var accumulatedContent = ""  // 用于累加内容

    networkManager.sendChatRequest(
      content: text,
      onContentReceived: { [weak self] content in
        // 接收到内容时，累加到现有内容上
        accumulatedContent += content

        DispatchQueue.main.async {
          if let i = self?.messages.firstIndex(where: {
            $0.id == botId
          }) {
            withAnimation {
              self?.messages[i] = Message(
                id: botId,
                sentAt: self?.messages[i].sentAt
                  ?? Date().timeIntervalSince1970,
                readReceipt: .seen,
                style: .text(accumulatedContent),  // 使用累加后的内容
                sender: User.chatBot
              )
            }
          }
        }
      },
      onError: { [weak self] error in
        // 发生错误时，显示错误消息
        DispatchQueue.main.async {
          if let i = self?.messages.firstIndex(where: {
            $0.id == botId
          }) {
            withAnimation {
              self?.messages[i] = Message(
                id: botId,
                sentAt: self?.messages[i].sentAt
                  ?? Date().timeIntervalSince1970,
                readReceipt: .seen,
                style: .text(
                  "抱歉，发生了错误：\(error.localizedDescription)"
                ),
                sender: User.chatBot
              )
            }
          }
        }
        print("网络请求错误: \(error)")
      }
    )
  }

  func parseResponse(_ response: String) -> String? {
    let responseData = response.data(using: .utf8)!
    let json =
      try? JSONSerialization.jsonObject(with: responseData, options: [])
      as? [String: Any]
    let choices = json?["choices"] as? [[String: Any]]
    let text = choices?.first?["text"] as? String
    return text?.trimmingCharacters(in: .newlines)
  }
}
