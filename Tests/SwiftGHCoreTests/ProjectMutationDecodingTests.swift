import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct ProjectMutationDecodingTests {
    @Test func decodesCreateProjectResponse() throws {
        let json = #"""
            {"createProjectV2":{"projectV2":{"id":"PVT_x","number":7,"title":"My Project","shortDescription":null,"url":"https://github.com/users/me/projects/7","closed":false,"public":false,"readme":null,"createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z"}}}
            """#
        let response = try JSONDecoder.gitHub().decode(
            CreateProjectResponse.self, from: Data(json.utf8))
        #expect(response.createProjectV2.projectV2.title == "My Project")
        #expect(response.createProjectV2.projectV2.number == 7)
    }

    @Test func decodesAddItemByIdResponse() throws {
        let json = #"""
            {"addProjectV2ItemById":{"item":{"id":"PVTI_abc","type":"ISSUE"}}}
            """#
        let response = try JSONDecoder.gitHub().decode(
            AddProjectItemByIdResponse.self, from: Data(json.utf8))
        #expect(response.addProjectV2ItemById.item.id == "PVTI_abc")
        #expect(response.addProjectV2ItemById.item.type == "ISSUE")
    }

    @Test func decodesPolymorphicFields() throws {
        // Three field shapes: ProjectV2Field, ProjectV2IterationField,
        // ProjectV2SingleSelectField. Only the third has options.
        let json = #"""
            {"viewer":{"projectV2":{"fields":{"totalCount":3,"nodes":[
              {"__typename":"ProjectV2Field","id":"a","name":"Title","dataType":"TITLE"},
              {"__typename":"ProjectV2IterationField","id":"b","name":"Sprint","dataType":"ITERATION"},
              {"__typename":"ProjectV2SingleSelectField","id":"c","name":"Status","dataType":"SINGLE_SELECT","options":[{"id":"o1","name":"Todo"},{"id":"o2","name":"In progress"}]}
            ]}}}}
            """#
        let response = try JSONDecoder.gitHub().decode(
            ProjectFieldsResponse.self, from: Data(json.utf8))
        let nodes = try #require(response.viewer?.projectV2?.fields.nodes)
        #expect(nodes.count == 3)
        #expect(nodes[0].dataType == "TITLE")
        #expect(nodes[0].options == nil)
        #expect(nodes[2].dataType == "SINGLE_SELECT")
        #expect(nodes[2].options?.count == 2)
        #expect(nodes[2].options?.first?.name == "Todo")
    }

    @Test func decodesResourceIdResponse() throws {
        let json = #"""
            {"resource":{"__typename":"Issue","id":"I_kw"}}
            """#
        let response = try JSONDecoder.gitHub().decode(
            ResourceIdResponse.self, from: Data(json.utf8))
        #expect(response.resource?.id == "I_kw")
        #expect(response.resource?.typename == "Issue")
    }

    @Test func decodesNullResource() throws {
        let json = #"{"resource":null}"#
        let response = try JSONDecoder.gitHub().decode(
            ResourceIdResponse.self, from: Data(json.utf8))
        #expect(response.resource == nil)
    }
}
