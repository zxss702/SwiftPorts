import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct WorkflowJobDecodingTests {
    @Test func decodesJobListEnvelope() throws {
        let json = #"""
            {
              "total_count": 2,
              "jobs": [
                {
                  "id": 100,
                  "run_id": 5,
                  "run_url": "https://api.github.com/repos/x/y/actions/runs/5",
                  "node_id": "JOB_kw1",
                  "head_sha": "abc",
                  "url": "https://api.github.com/repos/x/y/actions/jobs/100",
                  "html_url": "https://github.com/x/y/actions/runs/5/job/100",
                  "status": "completed",
                  "conclusion": "success",
                  "created_at": "2024-01-01T00:00:00Z",
                  "started_at": "2024-01-01T00:00:01Z",
                  "completed_at": "2024-01-01T00:00:30Z",
                  "name": "build",
                  "steps": [
                    {"name":"Set up","status":"completed","conclusion":"success","number":1,"started_at":"2024-01-01T00:00:01Z","completed_at":"2024-01-01T00:00:02Z"},
                    {"name":"Build","status":"completed","conclusion":"success","number":2,"started_at":"2024-01-01T00:00:02Z","completed_at":"2024-01-01T00:00:30Z"}
                  ]
                },
                {
                  "id": 101,
                  "run_id": 5,
                  "run_url": "https://api.github.com/repos/x/y/actions/runs/5",
                  "node_id": "JOB_kw2",
                  "head_sha": "abc",
                  "url": "https://api.github.com/repos/x/y/actions/jobs/101",
                  "html_url": null,
                  "status": "completed",
                  "conclusion": "skipped",
                  "name": "deploy",
                  "steps": null
                }
              ]
            }
            """#
        let envelope = try JSONDecoder.gitHub().decode(
            WorkflowJobList.self, from: Data(json.utf8))
        #expect(envelope.totalCount == 2)
        #expect(envelope.jobs.count == 2)
        #expect(envelope.jobs[0].name == "build")
        #expect(envelope.jobs[0].steps?.count == 2)
        #expect(envelope.jobs[1].conclusion == "skipped")
        #expect(envelope.jobs[1].steps == nil)
    }

    @Test func decodesArtifactList() throws {
        let json = #"""
            {
              "total_count": 1,
              "artifacts": [{
                "id": 99,
                "node_id": "ART_kw",
                "name": "logs",
                "size_in_bytes": 12345,
                "url": "https://api.github.com/repos/x/y/actions/artifacts/99",
                "archive_download_url": "https://api.github.com/repos/x/y/actions/artifacts/99/zip",
                "expired": false,
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z",
                "expires_at": "2024-04-01T00:00:00Z",
                "workflow_run": {"id": 5, "repository_id": 1, "head_branch": "main", "head_sha": "abc"}
              }]
            }
            """#
        let envelope = try JSONDecoder.gitHub().decode(
            WorkflowArtifactList.self, from: Data(json.utf8))
        #expect(envelope.artifacts.count == 1)
        #expect(envelope.artifacts[0].name == "logs")
        #expect(envelope.artifacts[0].sizeInBytes == 12345)
        #expect(envelope.artifacts[0].expired == false)
    }
}
