// SPDX-License-Identifier: GPL-2.0-only
import XCTest
@testable import SFTCore

final class H264Tests: XCTestCase {
    let nal = Data([0, 0, 0, 1, 0x67, 0x64, 0, 0, 1, 0x68, 0x12, 0, 0, 1, 0x65, 9])

    func testMixedStartCodes() {
        let units = H264.nalUnits(in: nal)
        XCTAssertEqual(units.count, 3)
        XCTAssertEqual(units[0].type, 7)
        XCTAssertEqual(units[0].data, Data([0x67, 0x64]))
        XCTAssertEqual(units[1].type, 8)
        XCTAssertEqual(units[1].data, Data([0x68, 0x12]))
        XCTAssertEqual(units[2].type, 5)
        XCTAssertEqual(units[2].data, Data([0x65, 9]))
    }

    func testParameterSets() throws {
        let (sps, pps) = try H264.parameterSets(in: nal)
        XCTAssertEqual(sps, Data([0x67, 0x64]))
        XCTAssertEqual(pps, Data([0x68, 0x12]))
        XCTAssertThrowsError(try H264.parameterSets(in: Data([0, 0, 1, 0x65, 1]))) {
            XCTAssertEqual($0 as? H264Error, .missingParameterSets)
        }
    }

    func testIsIDR() {
        XCTAssertTrue(H264.isIDR(nal))
        XCTAssertFalse(H264.isIDR(Data([0, 0, 0, 1, 0x41, 7])))
        XCTAssertFalse(H264.isIDR(Data()))
    }

    func testAccessUnitDropsParameterAndAUD() throws {
        var frame = Data([0, 0, 0, 1, 0x09, 0x10])
        frame.append(nal)
        frame.append(Data([0, 0, 0, 1, 0x06, 5, 5]))
        frame.append(Data([0, 0, 0, 1, 0x41, 7]))
        let unit = try H264.accessUnit(from: frame)
        XCTAssertEqual(unit, Data([
            0, 0, 0, 2, 0x65, 9,
            0, 0, 0, 3, 0x06, 5, 5,
            0, 0, 0, 2, 0x41, 7,
        ]))
    }

    func testAccessUnitRejectsMalformed() {
        XCTAssertThrowsError(try H264.accessUnit(from: Data())) {
            XCTAssertEqual($0 as? H264Error, .empty)
        }
        XCTAssertThrowsError(try H264.accessUnit(from: Data([0, 0, 1]))) {
            XCTAssertEqual($0 as? H264Error, .truncatedNALUnit)
        }
        XCTAssertThrowsError(try H264.accessUnit(from: Data([0, 0, 0, 1, 0x67, 0x64, 0, 0, 0, 1]))) {
            XCTAssertEqual($0 as? H264Error, .truncatedNALUnit)
        }
        XCTAssertThrowsError(try H264.accessUnit(from: Data([0, 0, 0, 1, 0x67, 0x64]))) {
            XCTAssertEqual($0 as? H264Error, .noDecodableNALUnits)
        }
        XCTAssertThrowsError(try H264.accessUnit(from: Data([9, 9, 9]))) {
            XCTAssertEqual($0 as? H264Error, .empty)
        }
    }
}
