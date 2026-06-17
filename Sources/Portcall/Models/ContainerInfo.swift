import Foundation

/// A running container that publishes one or more host ports.
struct ContainerInfo: Sendable, Hashable {
    let id: String      // short (12-char) container id
    let name: String
    let image: String
}
