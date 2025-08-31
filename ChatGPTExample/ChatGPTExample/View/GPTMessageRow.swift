//
//  GPTMessageRow.swift
//  ChatGPTExample
//
//  Created by Jaesung Lee on 2023/03/14.
//

import ChatUI
import SwiftUI

struct GPTMessageRow: View {
  let message: Message
  let isLastMessage: Bool

  var body: some View {
    MessageRow(
      message: message,
      showsUsername: false,
      showsProfileImage: false
    )
  }
}
