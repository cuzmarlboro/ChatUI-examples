import Foundation

/// SSE管理器 - 专门处理Server-Sent Events连接和数据流
class SSEManager: ObservableObject {

  // MARK: - 属性

  /// 当前活跃的SSE连接
  private var currentConnection: URLSessionDataTask?

  /// 数据缓冲区 - 用于处理分片数据
  private var dataBuffer = Data()

  /// 连接状态
  @Published var isConnected = false

  // MARK: - 公共方法

  /// 建立SSE连接
  /// - Parameters:
  ///   - url: SSE端点URL
  ///   - onMessage: 接收到消息时的回调
  ///   - onError: 发生错误时的回调
  ///   - onComplete: 连接完成时的回调
  func connect(
    to url: URL,
    onMessage: @escaping (SSEMessage) -> Void,
    onError: @escaping (Error) -> Void,
    onComplete: @escaping () -> Void
  ) {
    // 取消之前的连接
    disconnect()

    // 创建URLRequest
    var request = URLRequest(url: url)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    request.setValue("keep-alive", forHTTPHeaderField: "Connection")

    // 创建URLSession配置
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 300  // 5分钟超时

    let session = URLSession(configuration: config)

    // 发起请求
    currentConnection = session.dataTask(with: request) { [weak self] data, response, error in
      DispatchQueue.main.async {
        self?.handleDataTaskResponse(
          data: data,
          response: response,
          error: error,
          onMessage: onMessage,
          onError: onError,
          onComplete: onComplete
        )
      }
    }

    currentConnection?.resume()
    isConnected = true
  }

  /// 断开SSE连接
  func disconnect() {
    currentConnection?.cancel()
    currentConnection = nil
    isConnected = false
    dataBuffer.removeAll()
  }

  // MARK: - 私有方法

  /// 处理数据任务响应
  private func handleDataTaskResponse(
    data: Data?,
    response: URLResponse?,
    error: Error?,
    onMessage: @escaping (SSEMessage) -> Void,
    onError: @escaping (Error) -> Void,
    onComplete: @escaping () -> Void
  ) {
    // 检查错误
    if let error = error {
      isConnected = false
      onError(SSEError.connectionError(error))
      return
    }

    // 检查HTTP状态码
    if let httpResponse = response as? HTTPURLResponse {
      guard (200...299).contains(httpResponse.statusCode) else {
        isConnected = false
        onError(SSEError.httpError(httpResponse.statusCode))
        return
      }
    }

    // 处理数据
    if let data = data {
      processIncomingData(data, onMessage: onMessage)
    }
  }

  /// 处理传入的数据
  private func processIncomingData(_ data: Data, onMessage: @escaping (SSEMessage) -> Void) {
    // 将新数据添加到缓冲区
    dataBuffer.append(data)

    // 将缓冲区数据转换为字符串
    guard let dataString = String(data: dataBuffer, encoding: .utf8) else {
      return
    }

    // 按行分割数据
    let lines = dataString.components(separatedBy: .newlines)

    // 处理完整的行
    var processedLines = 0
    for (index, line) in lines.enumerated() {
      // 跳过空行和注释行
      guard !line.isEmpty && !line.hasPrefix(":") else {
        processedLines += 1
        continue
      }

      // 检查是否是数据行
      if line.hasPrefix("data:") {
        let jsonString = String(line.dropFirst(5))  // 移除 "data:" 前缀
        if let message = parseSSEMessage(from: jsonString) {
          onMessage(message)
        }
        processedLines += 1
      }
    }

    // 移除已处理的行，保留未完成的数据
    if processedLines > 0 {
      let remainingData = dataString.components(separatedBy: .newlines).dropFirst(processedLines)
        .joined(separator: "\n")
      dataBuffer = remainingData.data(using: .utf8) ?? Data()
    }
  }

  /// 解析SSE消息
  private func parseSSEMessage(from jsonString: String) -> SSEMessage? {
    // 清理JSON字符串
    let cleanJSON = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

    // 转换为Data
    guard let jsonData = cleanJSON.data(using: .utf8) else {
      return nil
    }

    // 解码JSON
    do {
      let message = try JSONDecoder().decode(SSEMessage.self, from: jsonData)
      return message
    } catch {
      print("SSE消息解析失败: \(error), JSON: \(cleanJSON)")
      return nil
    }
  }
}

// MARK: - 错误类型

/// SSE相关错误
enum SSEError: Error, LocalizedError {
  case connectionError(Error)
  case httpError(Int)
  case invalidData

  var errorDescription: String? {
    switch self {
    case .connectionError(let error):
      return "连接错误: \(error.localizedDescription)"
    case .httpError(let statusCode):
      return "HTTP错误: \(statusCode)"
    case .invalidData:
      return "无效的数据格式"
    }
  }
}
