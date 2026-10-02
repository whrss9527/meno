import XCTest
@testable import MenoCore

final class UpdateReleaseTests: XCTestCase {
    private let repository = "whrss9527/meno"

    func testDecodesTheLatestReleaseResponse() throws {
        let json = """
        {
          "tag_name": "v0.7.0",
          "html_url": "https://github.com/whrss9527/meno/releases/tag/v0.7.0",
          "draft": false,
          "prerelease": false,
          "published_at": "2026-10-01T09:05:20Z",
          "body": "Meno 0.7.0 installs updates itself.",
          "assets": [
            {
              "name": "Meno.zip",
              "size": 4178208,
              "digest": "sha256:9F86D081884C7D659A2FEAA0C55AD015A3BF4F1B2B0B822CD15D6C15B0F00A08",
              "browser_download_url": "https://github.com/whrss9527/meno/releases/download/v0.7.0/Meno.zip"
            }
          ]
        }
        """
        let release = try JSONDecoder().decode(UpdateRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, AppVersion("0.7.0"))
        XCTAssertEqual(release.body, "Meno 0.7.0 installs updates itself.")
        XCTAssertEqual(release.publishedAt, Date(timeIntervalSince1970: 1_790_845_520))
        XCTAssertFalse(release.isDraft)
        XCTAssertFalse(release.isPrerelease)
        let archive = try XCTUnwrap(release.appArchive(repository: repository))
        XCTAssertEqual(archive.size, 4_178_208)
        XCTAssertEqual(archive.sha256, "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
    }

    func testOlderResponsesWithoutAssetsOrDigestsStillDecode() throws {
        let json = """
        {"tag_name": "v0.6.0", "html_url": "https://github.com/whrss9527/meno/releases/tag/v0.6.0"}
        """
        let release = try JSONDecoder().decode(UpdateRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.assets, [])
        XCTAssertNil(release.appArchive(repository: repository))
        XCTAssertNil(release.body)
        XCTAssertNil(release.publishedAt)

        let asset = UpdateRelease.Asset(name: "Meno.zip", downloadURL: URL(string: "https://github.com/x")!)
        XCTAssertNil(asset.sha256)
    }

    func testRejectsMalformedDigests() {
        let url = URL(string: "https://github.com/x")!
        for digest in ["md5:abc", "sha256:", "sha256:xyz", "sha256:" + String(repeating: "a", count: 63), "sha512:" + String(repeating: "a", count: 64)] {
            XCTAssertNil(UpdateRelease.Asset(name: "Meno.zip", downloadURL: url, digest: digest).sha256, digest)
        }
    }

    func testOnlyTakesTheAppFromThisRelease() {
        func release(_ urls: [(String, String)]) -> UpdateRelease {
            UpdateRelease(
                tagName: "v0.7.0",
                htmlURL: URL(string: "https://github.com/whrss9527/meno/releases/tag/v0.7.0")!,
                assets: urls.map { UpdateRelease.Asset(name: $0.0, downloadURL: URL(string: $0.1)!) }
            )
        }
        let good = "https://github.com/whrss9527/meno/releases/download/v0.7.0/Meno.zip"
        XCTAssertEqual(release([("Meno.zip", good)]).appArchive(repository: repository)?.downloadURL.absoluteString, good)
        // Plain HTTP, other hosts, other repositories and other releases are not used.
        for url in [
            "http://github.com/whrss9527/meno/releases/download/v0.7.0/Meno.zip",
            "https://example.com/whrss9527/meno/releases/download/v0.7.0/Meno.zip",
            "https://github.com/someone/meno/releases/download/v0.7.0/Meno.zip",
            "https://github.com/whrss9527/meno/releases/download/v0.6.0/Meno.zip",
            "https://github.com/whrss9527/meno/releases/download/v0.7.0/",
        ] {
            XCTAssertNil(release([("Meno.zip", url)]).appArchive(repository: repository), url)
        }
        // Other files are skipped, and a renamed archive is still found.
        let renamed = "https://github.com/whrss9527/meno/releases/download/v0.7.0/Meno-0.7.0.zip"
        let archive = release([
            ("Source.tar.gz", "https://github.com/whrss9527/meno/releases/download/v0.7.0/Source.tar.gz"),
            ("Meno-0.7.0.zip", renamed),
        ]).appArchive(repository: repository)
        XCTAssertEqual(archive?.name, "Meno-0.7.0.zip")
    }
}
