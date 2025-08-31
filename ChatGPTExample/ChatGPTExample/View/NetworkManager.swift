import Foundation

/// 网络管理器 - 负责处理HTTP请求和SSE连接
class NetworkManager: NSObject, ObservableObject {

  // MARK: - 属性

  /// 基础URL
  private let baseURL = "http://182.43.79.29:8001"

  /// 聊天接口路径
  private let chatPath = "/open/flow/run/invoke"

  /// 当前活跃的SSE连接
  private var currentSSEConnection: URLSessionDataTask?

  /// URLSession实例
  private var session: URLSession?

  /// 数据缓冲区 - 用于处理分片数据
  private var dataBuffer = Data()

  /// 回调闭包
  private var onContentReceived: ((String) -> Void)?
  private var onError: ((Error) -> Void)?

  override init() {
    super.init()
  }

  // MARK: - 公共方法

  /// 发送聊天请求并建立SSE连接
  /// - Parameters:
  ///   - content: 用户输入的消息内容
  ///   - onContentReceived: 接收到内容时的回调，用于实现打字机效果
  ///   - onError: 发生错误时的回调
  func sendChatRequest(
    content: String,
    onContentReceived: @escaping (String) -> Void,
    onError: @escaping (Error) -> Void
  ) {
    // 保存回调
    self.onContentReceived = onContentReceived
    self.onError = onError

    // 创建请求参数
    let request = ChatRequest(content: content)

    // 构建URL
    guard let url = URL(string: baseURL + chatPath) else {
      onError(NetworkError.invalidURL)
      return
    }

    // 创建URLRequest
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue(
      "application/json",
      forHTTPHeaderField: "Content-Type"
    )
    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    urlRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    urlRequest.setValue("keep-alive", forHTTPHeaderField: "Connection")

    // 编码请求体
    do {
      let jsonData = try JSONEncoder().encode(request)
      urlRequest.httpBody = jsonData

      // 打印请求体内容
      if let jsonString = String(data: jsonData, encoding: .utf8) {
        print("=== 发送给 \(chatPath) 的请求体 ===")
        print("URL: \(url)")
        print("请求体: \(jsonString)")
        print("================================")
      }

    } catch {
      onError(NetworkError.encodingError(error))
      return
    }

    // 创建URLSession配置
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 300  // 5分钟超时

    // 创建URLSession，设置delegate
    session = URLSession(
      configuration: config,
      delegate: self,
      delegateQueue: nil
    )

    // 取消之前的连接
    currentSSEConnection?.cancel()

    // 清空数据缓冲区
    dataBuffer.removeAll()

    // 发起请求
    currentSSEConnection = session?.dataTask(with: urlRequest)
    currentSSEConnection?.resume()
  }

  /// 取消当前的SSE连接
  func cancelCurrentConnection() {
    currentSSEConnection?.cancel()
    currentSSEConnection = nil
    session = nil
    dataBuffer.removeAll()
  }
}

// MARK: - URLSessionDataDelegate

extension NetworkManager: URLSessionDataDelegate {

  /// 接收到数据时的回调
  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    // 将新数据添加到缓冲区
    dataBuffer.append(data)

    // 处理接收到的数据
    processReceivedData()
  }

  /// 任务完成时的回调
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error = error {
      DispatchQueue.main.async {
        self.onError?(NetworkError.networkError(error))
      }
    }
  }

  /// 接收到响应时的回调
  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    // 检查HTTP状态码
    if let httpResponse = response as? HTTPURLResponse {
      guard (200...299).contains(httpResponse.statusCode) else {
        DispatchQueue.main.async {
          self.onError?(
            NetworkError.httpError(httpResponse.statusCode)
          )
        }
        completionHandler(.cancel)
        return
      }
    }

    // 继续接收数据
    completionHandler(.allow)
  }
}

// MARK: - 私有方法

extension NetworkManager {

  /// 处理接收到的数据
  private func processReceivedData() {
    // 将缓冲区数据转换为字符串
    guard let dataString = String(data: dataBuffer, encoding: .utf8) else {
      return
    }

    // 按行分割数据
    let lines = dataString.components(separatedBy: .newlines)

    // 处理完整的行
    var processedLines = 0
    for line in lines {
      // 跳过空行和注释行
      guard !line.isEmpty && !line.hasPrefix(":") else {
        processedLines += 1
        continue
      }

      // 检查是否是数据行
      if line.hasPrefix("data:") {
        let jsonString = String(line.dropFirst(5))  // 移除 "data:" 前缀
        processJSONData(jsonString: jsonString)
        processedLines += 1
      }
    }

    // 移除已处理的行，保留未完成的数据
    if processedLines > 0 {
      let remainingData = dataString.components(separatedBy: .newlines)
        .dropFirst(processedLines)
        .joined(separator: "\n")
      dataBuffer = remainingData.data(using: .utf8) ?? Data()
    }
  }

  /// 处理JSON数据
  private func processJSONData(jsonString: String) {
    // 清理JSON字符串
    let cleanJSON = jsonString.trimmingCharacters(
      in: .whitespacesAndNewlines
    )

    // 转换为Data
    guard let jsonData = cleanJSON.data(using: .utf8) else {
      return
    }

    // 解码JSON
    do {
      let sseMessage = try JSONDecoder().decode(
        SSEMessage.self,
        from: jsonData
      )

      // 只处理llmStream类型的消息
      if sseMessage.msgType == .llmStream {
        if let content = sseMessage.data.content, !content.isEmpty {
          // 在主线程调用回调
          DispatchQueue.main.async {
            self.onContentReceived?(content)
          }
        }
      }
    } catch {
      // JSON解析失败，静默处理
      print("JSON解析失败: \(error)")
    }
  }
}

// MARK: - 错误类型

/// 网络相关错误
enum NetworkError: Error, LocalizedError {
  case invalidURL
  case encodingError(Error)
  case networkError(Error)
  case httpError(Int)
  case noData

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "无效的URL"
    case .encodingError(let error):
      return "编码错误: \(error.localizedDescription)"
    case .networkError(let error):
      return "网络错误: \(error.localizedDescription)"
    case .httpError(let statusCode):
      return "HTTP错误: \(statusCode)"
    case .noData:
      return "没有接收到数据"
    }
  }
}
