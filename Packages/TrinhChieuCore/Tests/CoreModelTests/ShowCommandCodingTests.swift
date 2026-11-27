import Foundation
import Testing

@testable import CoreModel

/// Hợp đồng JSON của lệnh cho remote và nhật ký: mỗi case một chuỗi cố định.
@Suite("ShowCommand: chuỗi JSON cố định")
struct ShowCommandCodingTests {
    static let plan = "00000000-0000-4000-8000-000000000001"
    static let item = "00000000-0000-4000-8000-000000000002"
    static let presentation = "00000000-0000-4000-8000-000000000003"

    static let cases: [(ShowCommand, String)] = [
        (.loadPlan(planID: fixedID(1)), #"{"planID":"\#(plan)","type":"loadPlan"}"#),
        (.loadPlan(planID: nil), #"{"type":"loadPlan"}"#),
        (
            .selectItem(.planItem(planID: fixedID(1), itemID: fixedID(2))),
            #"{"source":{"itemID":"\#(item)","planID":"\#(plan)","type":"planItem"},"type":"selectItem"}"#
        ),
        (
            .goLive(.presentation(id: fixedID(3), arrangementID: nil), slideIndex: 2),
            #"{"slideIndex":2,"source":{"id":"\#(presentation)","type":"presentation"},"type":"goLive"}"#
        ),
        (
            .goLive(.presentation(id: fixedID(3), arrangementID: fixedID(2)), slideIndex: 0),
            #"{"slideIndex":0,"source":{"arrangementID":"\#(item)","id":"\#(presentation)","type":"presentation"},"type":"goLive"}"#
        ),
        (
            .goLive(.scripture(translation: "vi1925", reference: "Giăng 3:16-18"), slideIndex: 1),
            #"{"slideIndex":1,"source":{"reference":"Giăng 3:16-18","translation":"vi1925","type":"scripture"},"type":"goLive"}"#
        ),
        (
            .goLive(.media("a1b2c3d4e5f6"), slideIndex: 0),
            #"{"slideIndex":0,"source":{"mediaID":"a1b2c3d4e5f6","type":"media"},"type":"goLive"}"#
        ),
        (.next, #"{"type":"next"}"#),
        (.previous, #"{"type":"previous"}"#),
        (.clearLayer(.slide), #"{"layer":"slide","type":"clearLayer"}"#),
        (.clearLayer(.background), #"{"layer":"background","type":"clearLayer"}"#),
        (.clearAll, #"{"type":"clearAll"}"#),
        (.setFreeze(true), #"{"enabled":true,"type":"setFreeze"}"#),
        (.setRehearsal(false), #"{"enabled":false,"type":"setRehearsal"}"#),
        (
            .contentDidChange(ids: [fixedID(3), fixedID(1)]),
            #"{"ids":["\#(plan)","\#(presentation)"],"type":"contentDidChange"}"#
        ),
    ]

    @Test("Mỗi case mã hoá đúng chuỗi JSON cố định", arguments: 0..<cases.count)
    func encodesFixedJSON(index: Int) throws {
        let (command, json) = Self.cases[index]
        let data = try ShowCommand.makeEncoder().encode(command)
        #expect(String(decoding: data, as: UTF8.self) == json)
    }

    @Test("Mỗi chuỗi JSON cố định giải mã ra đúng lệnh", arguments: 0..<cases.count)
    func decodesFixedJSON(index: Int) throws {
        let (command, json) = Self.cases[index]
        let decoded = try JSONDecoder().decode(ShowCommand.self, from: Data(json.utf8))
        #expect(decoded == command)
    }

    @Test("Bảng test phủ đủ mọi case lệnh")
    func coversEveryCommand() throws {
        var types = Set<String>()
        for (_, json) in Self.cases {
            let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            types.insert(try #require(object?["type"] as? String))
        }
        let expected: Set<String> = [
            "loadPlan", "selectItem", "goLive", "next", "previous", "clearLayer", "clearAll", "setFreeze",
            "setRehearsal", "contentDidChange",
        ]
        #expect(types == expected)
    }

    @Test("Loại lệnh lạ thì báo lỗi")
    func unknownTypeFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ShowCommand.self, from: Data(#"{"type":"explode"}"#.utf8))
        }
    }
}
