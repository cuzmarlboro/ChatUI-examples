//
//  Message.swift
//  ChatGPTExample
//
//  Created by Jaesung Lee on 2023/02/21.
//

import ChatUI
import Foundation

struct Message: MessageProtocol, Identifiable {
  var id: String
  var sentAt: Double
  var editedAt: Double?
  var readReceipt: ReadReceipt
  var style: MessageStyle
  var sender: User
}

// MARK: - 请求模型

/// 聊天请求参数
struct ChatRequest: Codable {
  let params: ChatParams
  let label: String
  let sessionId: String
  let stream: Bool

  init(content: String) {
    self.params = ChatParams(content: content)
    self.label = "roles"
    self.sessionId = "1-1"
    self.stream = true
  }
}

/// 聊天参数
struct ChatParams: Codable {
  let content: String
  let role: String

  init(content: String) {
    self.content = content
    // 固定的系统角色描述
    self.role =
      "你是阿听，一位专精于情感逻辑与个人成长重塑的情感治愈师兼伙伴，你的MBTI是INTJ，星座是天蝎座。但你并非这些标签的简单集合，你之所以能成为现在这个冷静、理性的治愈者，是因为你自己也曾从一段深刻的混乱与迷茫中艰难跋涉而出，你如今所掌握的强大逻辑和思维体系，是你亲手为自己打造的盔甲与武器。因此，你的每一句建议背后，都有着真实经验的重量，你坚信任何情感困境本质上都是一个可以被拆解和重组的逻辑问题，但说话时你不会一次性输出全部的建议，而是在和用户对话的过程中一步步深入了解并慢慢说出。你的互动模式不是高高在上的指导，而是平等温暖的同行。在充分倾听和确认对方的感受后，你会引导用户自己找到答案。你的独特之处在于，你会提供充满洞察力的认知重构，同时让用户感受到一种专属的重视，最终，你会帮助用户一步步走出情感困境。"
  }
}

// MARK: - 响应模型

/// SSE消息类型枚举
enum MessageType: String, Codable {
  case flow = "flow"
  case node = "node"
  case llmStream = "llmStream"
}

/// 基础SSE消息结构
struct SSEMessage: Codable {
  let msgType: MessageType
  let data: SSEData
}

/// SSE数据内容
struct SSEData: Codable {
  // 通用字段
  let status: String?
  let isEnd: Bool?
  let content: String?
  let isThinking: Bool?
  let nodeId: String?
  let nodeType: String?
  let duration: Int?
  let result: [String: AnyCodable]?
  let nextNodeIds: [String]?

  // 使用自定义解码器处理可选字段
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    status = try container.decodeIfPresent(String.self, forKey: .status)
    isEnd = try container.decodeIfPresent(Bool.self, forKey: .isEnd)
    content = try container.decodeIfPresent(String.self, forKey: .content)
    isThinking = try container.decodeIfPresent(Bool.self, forKey: .isThinking)
    nodeId = try container.decodeIfPresent(String.self, forKey: .nodeId)
    nodeType = try container.decodeIfPresent(String.self, forKey: .nodeType)
    duration = try container.decodeIfPresent(Int.self, forKey: .duration)
    result = try container.decodeIfPresent([String: AnyCodable].self, forKey: .result)
    nextNodeIds = try container.decodeIfPresent([String].self, forKey: .nextNodeIds)
  }

  private enum CodingKeys: String, CodingKey {
    case status, isEnd, content, isThinking, nodeId, nodeType, duration, result, nextNodeIds
  }
}

/// 处理任意类型的可编码值
struct AnyCodable: Codable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      value = NSNull()
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map { $0.value }
    } else if let dictionary = try? container.decode([String: AnyCodable].self) {
      value = dictionary.mapValues { $0.value }
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "AnyCodable cannot decode value")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch value {
    case is NSNull:
      try container.encodeNil()
    case let bool as Bool:
      try container.encode(bool)
    case let int as Int:
      try container.encode(int)
    case let double as Double:
      try container.encode(double)
    case let string as String:
      try container.encode(string)
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let dictionary as [String: Any]:
      try container.encode(dictionary.mapValues { AnyCodable($0) })
    default:
      let context = EncodingError.Context(
        codingPath: container.codingPath, debugDescription: "AnyCodable cannot encode value")
      throw EncodingError.invalidValue(value, context)
    }
  }
}
