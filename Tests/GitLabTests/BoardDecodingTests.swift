import Foundation
import Testing
@testable import GitLab

@Suite struct BoardDecodingTests {
    @Test func decodesBoardWithoutLists() throws {
        let json = """
        {
          "id": 28, "name": "Smoke Test Board",
          "project_id": 168, "milestone": null, "assignee": null,
          "labels": [], "weight": null, "lists": [],
          "hide_backlog_list": false, "hide_closed_list": false
        }
        """.data(using: .utf8)!
        let b = try JSONDecoder.gitLab().decode(Board.self, from: json)
        #expect(b.id == 28)
        #expect(b.name == "Smoke Test Board")
        #expect(b.lists?.isEmpty == true)
    }

    @Test func decodesBoardWithLists() throws {
        let json = """
        {
          "id": 1, "name": "Sprint",
          "lists": [
            {
              "id": 100,
              "label": {"id": 5, "name": "ToDo", "color": "#aabbcc", "text_color": "#fff", "description": null},
              "position": 0,
              "max_issue_count": 5,
              "max_issue_weight": null,
              "limit_metric": "issue_count"
            }
          ]
        }
        """.data(using: .utf8)!
        let b = try JSONDecoder.gitLab().decode(Board.self, from: json)
        #expect(b.lists?.count == 1)
        let list = try #require(b.lists?.first)
        #expect(list.label?.name == "ToDo")
        #expect(list.maxIssueCount == 5)
    }
}
