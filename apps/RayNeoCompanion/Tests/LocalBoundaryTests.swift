import XCTest
@testable import RayNeoCompanion

final class LocalBoundaryTests: XCTestCase {
    func testEndpointNormalizationKeepsServicePathBinding() throws {
        XCTAssertEqual(try ModelEndpoint.canonicalize("  HTTPS://Example.COM:443/v1/  "), "https://example.com/v1")
        XCTAssertEqual(try ModelEndpoint.canonicalize("https://example.com/"), "https://example.com")
        XCTAssertNotEqual(try ModelEndpoint.canonicalize("https://example.com/v1"), try ModelEndpoint.canonicalize("https://example.com/other"))
        XCTAssertEqual(try ModelEndpoint.canonicalize("https://example.com/v1%2F/"), "https://example.com/v1%2F")
        XCTAssertNotEqual(try ModelEndpoint.canonicalize("https://example.com/v1%2F"), try ModelEndpoint.canonicalize("https://example.com/v1"))
    }

    func testEndpointRejectsHTTPAndEmbeddedSecrets() {
        for value in ["http://example.com", "https://user:password@example.com", "https://example.com?key=secret", "https://example.com#secret", "not an endpoint"] {
            XCTAssertThrowsError(try ModelEndpoint.canonicalize(value), value)
        }
    }

    func testPhonePaginationPreservesEveryGraphemeAndIsNotDeviceRule() {
        let input = String(repeating: "眼镜👨‍👩‍👧‍👦e\u{301}\n", count: 50)
        let pages = LocalPrompterPager.pages(input, charactersPerPage: 17)
        XCTAssertEqual(pages.joined(), input)
        XCTAssertTrue(pages.allSatisfy { $0.count <= 17 })
        XCTAssertEqual(LocalPrompterPager.pages(""), [])
        XCTAssertEqual(LocalPrompterPager.pages("abc", charactersPerPage: 0), [])
    }

    func testCredentialNeedsBoundEndpoint() {
        XCTAssertThrowsError(try CredentialVault.store("synthetic-not-a-real-key", for: ""))
        XCTAssertFalse(CredentialVault.hasKey(for: ""))
    }

    func testCredentialsDoNotCarryToAnotherEndpoint() throws {
        let suffix = UUID().uuidString.lowercased()
        let first = "https://first-\(suffix).invalid/v1"
        let second = "https://second-\(suffix).invalid/v1"
        defer { try? CredentialVault.remove(for: first); try? CredentialVault.remove(for: second) }
        try CredentialVault.store("synthetic-not-a-real-key", for: first)
        XCTAssertTrue(CredentialVault.hasKey(for: first))
        XCTAssertFalse(CredentialVault.hasKey(for: second))
        XCTAssertTrue(CredentialVault.hasKey(for: first + "/"))
        XCTAssertFalse(CredentialVault.hasKey(for: first + "/different"))
    }

    @MainActor func testTodoAndPrompterPersistenceIsLocal() throws {
        let suite = "companion-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompanionStore(defaults: defaults)
        store.addTodo("  "); XCTAssertTrue(store.todos.isEmpty)
        store.addTodo("  测试待办  ")
        let todo = try XCTUnwrap(store.todos.first)
        XCTAssertEqual(todo.title, "测试待办")
        store.toggleTodo(todo.id)
        store.savePrompter("测试提词稿")
        let restored = CompanionStore(defaults: defaults)
        XCTAssertEqual(restored.todos.count, 1)
        XCTAssertTrue(restored.todos[0].completed)
        XCTAssertEqual(restored.prompterText, "测试提词稿")
    }

    @MainActor func testConfigChangeDoesNotInheritOldCredential() throws {
        let suite = "companion-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let first = "https://\(UUID().uuidString.lowercased()).invalid/v1"
        let second = "https://\(UUID().uuidString.lowercased()).invalid/v1"
        defer { defaults.removePersistentDomain(forName: suite); try? CredentialVault.remove(for: first) }
        let store = CompanionStore(defaults: defaults)
        var config = ModelConfiguration(); config.endpoint = first
        try store.saveConfiguration(config, key: "synthetic-test-only")
        config.endpoint = second
        try store.saveConfiguration(config, key: "")
        XCTAssertEqual(store.configuration.endpoint, second)
        XCTAssertFalse(CredentialVault.hasKey(for: second))
        let serialized = try XCTUnwrap(defaults.data(forKey: "companion.v1.configuration"))
        XCTAssertFalse(String(decoding: serialized, as: UTF8.self).contains("synthetic-test-only"))
    }

    func testImportCopiesBytesAndNeverMovesSource() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.ogg")
        let bytes = Data((0..<150_000).map { UInt8($0 % 251) })
        try bytes.write(to: source, options: .withoutOverwriting)
        let destination = directory.appendingPathComponent("archive")
        let first = try RecordingFileImporter.copy(source: source, to: destination)
        let second = try RecordingFileImporter.copy(source: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(first.storedFilename)), bytes)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(second.storedFilename)), bytes)
        XCTAssertNotEqual(first.storedFilename, second.storedFilename)
        XCTAssertEqual(first.byteCount, 150_000)
    }

    func testImportRejectsOversizedAndEmptyWithoutDestinationCopy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        try Data(repeating: 42, count: 10).write(to: source, options: .withoutOverwriting)
        let destination = directory.appendingPathComponent("archive")
        XCTAssertThrowsError(try RecordingFileImporter.copy(source: source, to: destination, maximumBytes: 5))
        XCTAssertEqual(try Data(contentsOf: source).count, 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let empty = directory.appendingPathComponent("empty.wav")
        try Data().write(to: empty, options: .withoutOverwriting)
        XCTAssertThrowsError(try RecordingFileImporter.copy(source: empty, to: destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: empty.path))
    }

    func testImportRejectsSymbolicLinkWithoutModifyingTarget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        try Data([1, 2, 3]).write(to: source, options: .withoutOverwriting)
        let link = directory.appendingPathComponent("link.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try RecordingFileImporter.copy(source: link, to: directory.appendingPathComponent("archive")))
        XCTAssertEqual(try Data(contentsOf: source), Data([1, 2, 3]))
    }

    @MainActor func testAsyncImportPersistsOnlyAfterSuccessfulCopy() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "companion-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = directory.appendingPathComponent("source.wav")
        try Data([1, 2, 3, 4]).write(to: source, options: .withoutOverwriting)
        let store = CompanionStore(defaults: defaults, recordingRoot: directory.appendingPathComponent("archive"))
        try await store.importRecording(source)
        XCTAssertFalse(store.isImporting)
        XCTAssertEqual(store.recordings.count, 1)
        XCTAssertNotNil(store.recordingURL(store.recordings[0]))
        let restored = CompanionStore(defaults: defaults, recordingRoot: directory.appendingPathComponent("archive"))
        XCTAssertEqual(restored.recordings.count, 1)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("companion-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
