import Foundation

public protocol DeskService: Sendable {
    var events: AsyncStream<DeskEvent> { get }
    func scan()
    func connect(to id: DeskID)
    func disconnect()
    func send(_ command: DeskCommand)
}

