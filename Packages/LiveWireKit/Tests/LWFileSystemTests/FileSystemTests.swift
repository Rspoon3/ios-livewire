import Foundation
import Testing

@testable import LWFileSystem

/// The same behavior, checked against the real disk and the in-memory stand-in, so the stand-in can
/// be trusted in other tests.
@Suite struct FileSystemContractTests {
    private func systems() -> [(name: String, fs: any FileSystem, root: URL)] {
        let disk = DiskFileSystem()
        let root = disk.temporaryDirectory.appendingPathComponent("lw-fs-\(UUID().uuidString)", isDirectory: true)
        return [("disk", disk, root), ("memory", InMemoryFileSystem(), URL(filePath: "/memory/contract", directoryHint: .isDirectory))]
    }

    @Test func writeThenRead() throws {
        for (name, fs, root) in systems() {
            defer { try? fs.remove(root) }
            let file = root.appendingPathComponent("a.txt")
            try fs.createDirectory(at: root)
            try fs.write(Data("hello".utf8), to: file)
            #expect(try fs.readString(file) == "hello", "\(name)")
            try fs.write(Data("again".utf8), to: file, protection: .untilFirstUserAuthentication)
            #expect(try fs.readString(file) == "again", "\(name): overwrites")
        }
    }

    @Test func readingAMissingFileThrows() {
        for (name, fs, root) in systems() {
            #expect(throws: (any Error).self, "\(name)") { try fs.read(root.appendingPathComponent("nope")) }
        }
    }

    @Test func listingAndRemoving() throws {
        for (name, fs, root) in systems() {
            defer { try? fs.remove(root) }
            try fs.createDirectory(at: root)
            try fs.write(Data("1".utf8), to: root.appendingPathComponent("one.log"))
            try fs.write(Data("2".utf8), to: root.appendingPathComponent("two.log"))

            let names = try fs.contentsOfDirectory(at: root).map(\.lastPathComponent).sorted()
            #expect(names == ["one.log", "two.log"], "\(name)")

            try fs.remove(root.appendingPathComponent("one.log"))
            #expect(try fs.contentsOfDirectory(at: root).map(\.lastPathComponent) == ["two.log"], "\(name)")
            #expect(throws: (any Error).self, "\(name): removing twice") { try fs.remove(root.appendingPathComponent("one.log")) }
        }
    }

    @Test func copyKeepsTheContentAndRefusesToOverwrite() throws {
        for (name, fs, root) in systems() {
            defer { try? fs.remove(root) }
            try fs.createDirectory(at: root)
            let source = root.appendingPathComponent("a")
            let copy = root.appendingPathComponent("b")
            try fs.write(Data("x".utf8), to: source)

            try fs.copy(from: source, to: copy)
            #expect(try fs.readString(copy) == "x", "\(name)")
            #expect(throws: (any Error).self, "\(name): destination exists") { try fs.copy(from: source, to: copy) }
        }
    }

    @Test func aWrittenFileHasAModificationDate() throws {
        for (name, fs, root) in systems() {
            defer { try? fs.remove(root) }
            try fs.createDirectory(at: root)
            let file = root.appendingPathComponent("a")
            #expect(fs.modificationDate(of: file) == nil, "\(name)")
            try fs.write(Data("x".utf8), to: file)
            #expect(fs.modificationDate(of: file) != nil, "\(name)")
        }
    }
}

@Suite struct InMemoryFileSystemTests {
    @Test func failNextFailsOnceAndOnlyThatOperation() throws {
        let fs = InMemoryFileSystem()
        let file = URL(filePath: "/memory/a")
        fs.failNext(.write, with: CocoaError(.fileWriteOutOfSpace))

        #expect(throws: CocoaError.self) { try fs.write(Data(), to: file) }
        try fs.write(Data("ok".utf8), to: file)
        #expect(try fs.readString(file) == "ok")
    }

    @Test func appGroupsExistOnlyWhenGiven() {
        let container = URL(filePath: "/memory/Group")
        let fs = InMemoryFileSystem(appGroups: ["group.test": container])
        #expect(fs.sharedContainer(appGroup: "group.test") == container)
        #expect(fs.sharedContainer(appGroup: "group.other") == nil)
    }

    @Test func modificationDatesComeFromTheInjectedClock() throws {
        let fs = InMemoryFileSystem(now: { Date(timeIntervalSince1970: 500) })
        let file = URL(filePath: "/memory/a")
        try fs.write(Data(), to: file)
        #expect(fs.modificationDate(of: file) == Date(timeIntervalSince1970: 500))
    }
}
