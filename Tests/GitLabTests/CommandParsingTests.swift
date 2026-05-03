import ArgumentParser
import Foundation
import Testing
@testable import GlabCommand

/// Argv-only parsing tests for the issue + auth surface. No network.
@Suite struct CommandParsingTests {
    @Test func issueListAcceptsRepoFlag() throws {
        let cmd = try IssueList.parse(["--repo", "group/sub/repo"])
        #expect(cmd.repo?.pathSegments == ["group", "sub", "repo"])
    }

    @Test func issueListDefaultsToOpened() throws {
        let cmd = try IssueList.parse([])
        #expect(cmd.all == false)
        #expect(cmd.closed == false)
    }

    @Test func issueListLabelsRepeatable() throws {
        let cmd = try IssueList.parse(["-l", "bug", "-l", "needs-review"])
        #expect(cmd.labels == ["bug", "needs-review"])
    }

    @Test func issueListConfidentialAndJSON() throws {
        let cmd = try IssueList.parse(["-C", "--json"])
        #expect(cmd.confidential == true)
        #expect(cmd.json == true)
    }

    @Test func issueViewAcceptsURLArgument() throws {
        let cmd = try IssueView.parse([
            "https://gitlab.com/foo/bar/-/issues/9",
        ])
        #expect(cmd.issue == "https://gitlab.com/foo/bar/-/issues/9")
    }

    @Test func issueCreateRequiresTitle() {
        #expect(throws: (any Error).self) {
            _ = try IssueCreate.parse([])
        }
    }

    @Test func issueCreateLabelsAndAssignees() throws {
        let cmd = try IssueCreate.parse([
            "--title", "Bug",
            "-l", "ui", "-l", "ux",
            "-a", "alice", "-a", "bob",
        ])
        #expect(cmd.title == "Bug")
        #expect(cmd.labels == ["ui", "ux"])
        #expect(cmd.assignees == ["alice", "bob"])
    }

    @Test func issueUpdateAccepts() throws {
        let cmd = try IssueUpdate.parse([
            "12",
            "--title", "Better title",
            "-l", "needs-review",
            "-u", "bug",
            "-C",
            "--lock-discussion",
        ])
        #expect(cmd.title == "Better title")
        #expect(cmd.addLabels == ["needs-review"])
        #expect(cmd.removeLabels == ["bug"])
        #expect(cmd.confidential == true)
        #expect(cmd.lockDiscussion == true)
    }

    @Test func issueNoteRequiresMessage() {
        #expect(throws: (any Error).self) {
            _ = try IssueNote.parse(["1"])
        }
    }

    @Test func issueNoteAccepts() throws {
        let cmd = try IssueNote.parse(["1", "-m", "looking into it"])
        #expect(cmd.issue == "1")
        #expect(cmd.message == "looking into it")
    }

    @Test func issueCloseAccepts() throws {
        let cmd = try IssueClose.parse(["#42"])
        #expect(cmd.issue == "#42")
    }

    @Test func issueDeleteAccepts() throws {
        let cmd = try IssueDelete.parse(["7"])
        #expect(cmd.issue == "7")
    }

    @Test func authStatusHostnameOptional() throws {
        let withFlag = try AuthStatus.parse(["-h", "self.example.com"])
        #expect(withFlag.hostname == "self.example.com")
        let bare = try AuthStatus.parse([])
        #expect(bare.hostname == nil)
    }

    @Test func authLoginWithTokenFlag() throws {
        let cmd = try AuthLogin.parse(["--with-token"])
        #expect(cmd.withToken == true)
    }

    @Test func ciListAcceptsFilters() throws {
        let cmd = try CiList.parse([
            "-R", "labs/AgentCorp",
            "-s", "failed",
            "--ref", "main",
            "--source", "push",
            "-P", "10",
        ])
        #expect(cmd.repo?.fullPath == "labs/AgentCorp")
        #expect(cmd.status == "failed")
        #expect(cmd.ref == "main")
        #expect(cmd.source == "push")
        #expect(cmd.perPage == 10)
    }

    @Test func ciViewPipelineIDOptional() throws {
        let bare = try CiView.parse([])
        #expect(bare.pipelineId == nil)
        let withId = try CiView.parse(["1234"])
        #expect(withId.pipelineId == 1234)
    }

    @Test func ciTraceRequiresJob() {
        #expect(throws: (any Error).self) {
            _ = try CiTrace.parse([])
        }
    }

    @Test func ciTraceAcceptsJobNameOrID() throws {
        let byID = try CiTrace.parse(["123456"])
        #expect(byID.job == "123456")
        let byName = try CiTrace.parse(["lint"])
        #expect(byName.job == "lint")
    }

    @Test func ciStatusFlags() throws {
        let cmd = try CiStatus.parse(["--once", "-b", "main", "--poll-interval", "5"])
        #expect(cmd.once == true)
        #expect(cmd.branch == "main")
        #expect(cmd.pollInterval == 5)
    }

    @Test func ciRunVariablesRepeatable() throws {
        let cmd = try CiRun.parse([
            "-v", "FOO=bar",
            "-v", "BAZ=qux",
            "-b", "main",
        ])
        #expect(cmd.variables == ["FOO=bar", "BAZ=qux"])
        #expect(cmd.branch == "main")
    }

    @Test func ciRetryAndCancelAcceptID() throws {
        let r = try CiRetry.parse(["1234"])
        #expect(r.pipelineId == 1234)
        let c = try CiCancel.parse(["1234"])
        #expect(c.pipelineId == 1234)
    }

    // MARK: MR

    @Test func mrListAcceptsFilters() throws {
        let cmd = try MrList.parse([
            "-R", "labs/sandbox",
            "-l", "bug", "-l", "needs-review",
            "--source-branch", "feature/x",
            "--target-branch", "main",
            "--merged",
        ])
        #expect(cmd.repo?.fullPath == "labs/sandbox")
        #expect(cmd.labels == ["bug", "needs-review"])
        #expect(cmd.sourceBranch == "feature/x")
        #expect(cmd.targetBranch == "main")
        #expect(cmd.merged == true)
    }

    @Test func mrCreateRequiresTitle() {
        #expect(throws: (any Error).self) {
            _ = try MrCreate.parse([])
        }
    }

    @Test func mrCreateAccepts() throws {
        let cmd = try MrCreate.parse([
            "-t", "Add HELLO.md",
            "-d", "test body",
            "-s", "feature/hello",
            "-b", "main",
            "-l", "smoke",
            "--draft",
        ])
        #expect(cmd.title == "Add HELLO.md")
        #expect(cmd.sourceBranch == "feature/hello")
        #expect(cmd.targetBranch == "main")
        #expect(cmd.draft == true)
    }

    @Test func mrUpdateAcceptsDraftAndReady() throws {
        let d = try MrUpdate.parse(["1", "--draft"])
        #expect(d.draft == true)
        let r = try MrUpdate.parse(["1", "--ready"])
        #expect(r.ready == true)
    }

    @Test func mrMergeFlags() throws {
        let cmd = try MrMerge.parse([
            "1", "--squash", "--remove-source-branch",
            "--merge-commit-message", "merge msg",
        ])
        #expect(cmd.squash == true)
        #expect(cmd.removeSourceBranch == true)
        #expect(cmd.mergeCommitMessage == "merge msg")
    }

    @Test func mrCheckoutDefaults() throws {
        let cmd = try MrCheckout.parse(["1"])
        #expect(cmd.remote == "origin")
    }

    @Test func mrDiffWebFlag() throws {
        let cmd = try MrDiff.parse(["1", "-w"])
        #expect(cmd.web == true)
    }

    // MARK: Repo

    @Test func repoCreateAccepts() throws {
        let cmd = try RepoCreate.parse([
            "test-thing",
            "-h", "git.cocoanetics.com",
            "-g", "labs",
            "--visibility", "private",
            "--initialize-with-readme",
        ])
        #expect(cmd.name == "test-thing")
        #expect(cmd.hostname == "git.cocoanetics.com")
        #expect(cmd.group == "labs")
        #expect(cmd.visibility == "private")
        #expect(cmd.initializeWithReadme == true)
    }

    @Test func repoListGroupAndOwnedFlags() throws {
        let cmd = try RepoList.parse([
            "-g", "labs", "--owned", "-P", "50",
        ])
        #expect(cmd.group == "labs")
        #expect(cmd.owned == true)
        #expect(cmd.perPage == 50)
    }

    @Test func repoCloneArgsAndFlag() throws {
        let cmd = try RepoClone.parse(["labs/glab-sandbox", "/tmp/dest", "--https"])
        #expect(cmd.project.fullPath == "labs/glab-sandbox")
        #expect(cmd.directory == "/tmp/dest")
        #expect(cmd.https == true)
    }

    @Test func repoForkOptional() throws {
        let cmd = try RepoFork.parse(["src/repo", "-g", "labs"])
        #expect(cmd.project.fullPath == "src/repo")
        #expect(cmd.namespace == "labs")
    }

    @Test func repoDeleteRequiresYesOrConfirm() throws {
        let cmd = try RepoDelete.parse(["-R", "labs/x", "-y"])
        #expect(cmd.yes == true)
    }

    // MARK: Board

    @Test func boardListAccepts() throws {
        let cmd = try IssueBoardList.parse(["-R", "labs/x", "-P", "10"])
        #expect(cmd.repo?.fullPath == "labs/x")
        #expect(cmd.perPage == 10)
    }

    @Test func boardCreatePositionalName() throws {
        let cmd = try IssueBoardCreate.parse(["My Board"])
        #expect(cmd.positionalName == "My Board")
        #expect(cmd.name == nil)
    }

    @Test func boardCreateNameFlag() throws {
        let cmd = try IssueBoardCreate.parse(["-n", "My Board"])
        #expect(cmd.positionalName == nil)
        #expect(cmd.name == "My Board")
    }

    @Test func boardViewIdOptional() throws {
        let bare = try IssueBoardView.parse([])
        #expect(bare.boardId == nil)
        let withId = try IssueBoardView.parse(["28"])
        #expect(withId.boardId == 28)
    }

    @Test func boardViewWebFlag() throws {
        let cmd = try IssueBoardView.parse(["28", "-w"])
        #expect(cmd.web == true)
    }

    @Test func boardDeleteRequiresIdAndYes() throws {
        let cmd = try IssueBoardDelete.parse(["28", "-y"])
        #expect(cmd.boardId == 28)
        #expect(cmd.yes == true)
    }
}
