import XCTest
@testable import MenoCore

final class UpdateNotesTests: XCTestCase {
    private func release(_ tag: String, body: String? = nil, draft: Bool = false, prerelease: Bool = false) -> UpdateRelease {
        UpdateRelease(
            tagName: tag,
            htmlURL: URL(string: "https://github.com/whrss9527/meno/releases/tag/\(tag)")!,
            body: body ?? "Meno \(tag) notes.",
            isDraft: draft,
            isPrerelease: prerelease
        )
    }

    func testKeepsOneLanguageWithoutTheRepeatedSections() {
        let body = """
        Meno 0.12.1 puts a misplaced divider back right away.

        中文说明见下方。

        ## Fixed

        - **Dividers:** a divider dragged right of the Meno icon is put back.
        - Clicking a divider says how to show the items again.

        ## Install or update

        1. **From Meno 0.10.0 or later:** choose *Install and Relaunch*.

        Requires macOS 14 or later.

        ## Known limitations

        - Moving items briefly takes over the pointer.

        ---

        ## 修复

        - **分隔符：** 被拖到 Meno 图标右侧的分隔符会被移回。

        ## 安装与更新

        1. 选择“安装并重新打开”。

        ## 已知限制

        - 移动项目时会短暂接管指针。
        """
        XCTAssertEqual(UpdateNotes.blocks(of: body, chinese: false), [
            .paragraph("Meno 0.12.1 puts a misplaced divider back right away."),
            .heading("Fixed"),
            .item("**Dividers:** a divider dragged right of the Meno icon is put back."),
            .item("Clicking a divider says how to show the items again."),
        ])
        XCTAssertEqual(UpdateNotes.blocks(of: body, chinese: true), [
            .heading("修复"),
            .item("**分隔符：** 被拖到 Meno 图标右侧的分隔符会被移回。"),
        ])
    }

    func testJoinsWrappedLinesAndReadsWindowsLineEnds() {
        let body = "Intro line\r\ncontinues here.\r\n\r\n## New\r\n\r\n- An item\r\n  that wraps.\r\n- Another item."
        XCTAssertEqual(UpdateNotes.blocks(of: body, chinese: false), [
            .paragraph("Intro line continues here."),
            .heading("New"),
            .item("An item that wraps."),
            .item("Another item."),
        ])
        // Notes without a Chinese part are shown as they are.
        XCTAssertEqual(UpdateNotes.blocks(of: body, chinese: true), UpdateNotes.blocks(of: body, chinese: false))
    }

    func testListsEveryVersionAfterTheRunningOneNewestFirst() throws {
        let latest = release("v0.12.2")
        let releases = [
            // Published after the check found 0.12.2.
            release("v0.12.3"),
            release("v0.12.2"),
            release("v0.12.1"),
            release("v0.12.0"),
            release("v0.11.9-beta.1", prerelease: true),
            release("v0.11.5", draft: true),
            release("v0.11.0"),
            release("v0.10.1"),
        ]
        let notes = UpdateNotes(current: try XCTUnwrap(AppVersion("0.11.0")), latest: latest, releases: releases, chinese: false)
        XCTAssertEqual(notes.tagName, "v0.12.2")
        XCTAssertEqual(notes.versions.map(\.version.description), ["0.12.2", "0.12.1", "0.12.0"])
        XCTAssertEqual(notes.versions.first?.blocks, [.paragraph("Meno v0.12.2 notes.")])
        XCTAssertTrue(notes.isComplete)
    }

    func testFallsBackToTheLatestReleaseWithoutTheList() throws {
        let latest = release("v0.12.2", body: "## New\n\n- One thing.")
        let notes = UpdateNotes(current: try XCTUnwrap(AppVersion("0.11.0")), latest: latest, releases: nil, chinese: false)
        XCTAssertEqual(notes.versions.map(\.version.description), ["0.12.2"])
        XCTAssertEqual(notes.versions.first?.blocks, [.heading("New"), .item("One thing.")])
        XCTAssertFalse(notes.isComplete)
    }

    func testSaysWhenTheListDoesNotReachTheRunningVersion() throws {
        // A full page, newest first: 1.0.99 down to 1.0.0.
        let page = (0..<UpdateNotes.pageSize).reversed().map { release("v1.0.\($0)") }
        let latest = try XCTUnwrap(page.first)

        let behind = UpdateNotes(current: try XCTUnwrap(AppVersion("0.9.0")), latest: latest, releases: page, chinese: false)
        XCTAssertEqual(behind.versions.count, UpdateNotes.pageSize)
        XCTAssertFalse(behind.isComplete)

        let reached = UpdateNotes(current: try XCTUnwrap(AppVersion("1.0.0")), latest: latest, releases: page, chinese: false)
        XCTAssertEqual(reached.versions.last?.version, AppVersion("1.0.1"))
        XCTAssertTrue(reached.isComplete)
    }
}
